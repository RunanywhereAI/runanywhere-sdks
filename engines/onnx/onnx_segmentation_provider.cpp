/** @file onnx_segmentation_provider.cpp
 *  @brief Generic ONNX semantic-segmentation pipeline (SegFormer-architecture).
 *
 *  Model-agnostic: any semantic-segmentation ONNX exported with the standard
 *  `pixel_values` input / `logits` output contract loads here. The class count
 *  and label set are derived from `config.json` (`id2label`); the input size,
 *  normalization mean/std, and rescale factor are derived from
 *  `preprocessor_config.json`. No model is pinned, licensed, or checksummed —
 *  the model is just data, like every other capability (LLM, VLM, …).
 */

#include "onnx_segmentation_provider.h"

#include "rac_runtime_onnxrt.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <mutex>
#include <new>
#include <nlohmann/json.hpp>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_logger.h"

namespace runanywhere::segmentation {
namespace {

using json = nlohmann::json;
using runanywhere::runtime::onnxrt::ElementType;
using runanywhere::runtime::onnxrt::Session;
using runanywhere::runtime::onnxrt::SessionOptions;
using runanywhere::runtime::onnxrt::TensorInput;
using runanywhere::runtime::onnxrt::TensorOutput;

constexpr const char* kLogCategory = "Segmentation.ONNX";
constexpr const char* kModelFileName = "model.onnx";
constexpr const char* kConfigFileName = "config.json";
constexpr const char* kPreprocessorFileName = "preprocessor_config.json";
constexpr size_t kMaxSourceDimension = 4096;
constexpr size_t kMaxClassCount = 65535;  // class ids are stored as uint16_t
constexpr int kCoefficientBits = 22;

// ImageNet defaults (SegFormer-family preprocessing) when a preprocessor field
// is absent.
constexpr size_t kDefaultInputSize = 512;
constexpr std::array<float, 3> kDefaultMean = {0.485f, 0.456f, 0.406f};
constexpr std::array<float, 3> kDefaultStd = {0.229f, 0.224f, 0.225f};
constexpr float kDefaultRescale = 1.0f / 255.0f;

// Per-model parameters derived from the bundle sidecars at load time.
struct ModelParams {
    size_t input_width = kDefaultInputSize;
    size_t input_height = kDefaultInputSize;
    std::array<float, 3> mean = kDefaultMean;
    std::array<float, 3> stddev = kDefaultStd;
    float rescale = kDefaultRescale;
    bool do_normalize = true;
    bool do_rescale = true;
    std::vector<std::string> labels;  // from config.json id2label (may be empty)
};

struct ResampleCoefficients {
    std::vector<size_t> starts;
    std::vector<size_t> counts;
    std::vector<int32_t> values;
    size_t stride = 0;
};

bool checked_mul(size_t a, size_t b, size_t* out) {
    if (!out || (a != 0 && b > std::numeric_limits<size_t>::max() / a)) {
        return false;
    }
    *out = a * b;
    return true;
}

bool read_file(const std::filesystem::path& path, std::string* out) {
    if (!out) {
        return false;
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return false;
    }
    out->assign(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
    return stream.good() || stream.eof();
}

// Parse config.json id2label into an ordered label vector (0..N-1). Returns an
// empty vector when the file is absent/unparsable or has no usable id2label; in
// that case class labels are synthesized from the model output at runtime.
std::vector<std::string> derive_labels(const std::filesystem::path& config_path) {
    std::string bytes;
    if (!std::filesystem::is_regular_file(config_path) || !read_file(config_path, &bytes)) {
        return {};
    }
    json config;
    try {
        config = json::parse(bytes);
    } catch (const std::exception&) {
        return {};
    }
    const auto it = config.find("id2label");
    if (it == config.end() || !it->is_object() || it->empty() || it->size() > kMaxClassCount) {
        return {};
    }
    std::vector<std::string> labels;
    labels.reserve(it->size());
    for (size_t i = 0; i < it->size(); ++i) {
        const auto entry = it->find(std::to_string(i));
        if (entry == it->end() || !entry->is_string()) {
            // id2label is not a dense 0..N-1 string map — fall back to synthesis.
            return {};
        }
        labels.push_back(entry->get<std::string>());
    }
    return labels;
}

void apply_preprocessor(const std::filesystem::path& preprocessor_path, ModelParams* params) {
    std::string bytes;
    if (!std::filesystem::is_regular_file(preprocessor_path) ||
        !read_file(preprocessor_path, &bytes)) {
        return;  // keep SegFormer-family defaults
    }
    json pre;
    try {
        pre = json::parse(bytes);
    } catch (const std::exception&) {
        return;
    }

    params->do_normalize = pre.value("do_normalize", params->do_normalize);
    params->do_rescale = pre.value("do_rescale", params->do_rescale);
    params->rescale = static_cast<float>(pre.value("rescale_factor", double{params->rescale}));

    const auto size_it = pre.find("size");
    if (size_it != pre.end() && size_it->is_object()) {
        const int width = size_it->value("width", size_it->value("shortest_edge", 0));
        const int height = size_it->value("height", size_it->value("shortest_edge", 0));
        if (width > 0) {
            params->input_width = static_cast<size_t>(std::min<int>(width, kMaxSourceDimension));
        }
        if (height > 0) {
            params->input_height = static_cast<size_t>(std::min<int>(height, kMaxSourceDimension));
        }
    }

    const auto read_triplet = [&pre](const char* key, std::array<float, 3>* out) {
        const auto it = pre.find(key);
        if (it != pre.end() && it->is_array() && it->size() == 3) {
            for (size_t i = 0; i < 3; ++i) {
                if ((*it)[i].is_number()) {
                    (*out)[i] = (*it)[i].get<float>();
                }
            }
        }
    };
    read_triplet("image_mean", &params->mean);
    read_triplet("image_std", &params->stddev);
}

bool load_bundle_impl(const std::filesystem::path& model_path, std::filesystem::path* out_model,
                      ModelParams* out_params, std::string* error) {
    if (!out_model || !out_params || !error) {
        return false;
    }
    std::filesystem::path directory =
        std::filesystem::is_directory(model_path) ? model_path : model_path.parent_path();
    if (directory.empty()) {
        directory = ".";
    }

    std::filesystem::path model =
        std::filesystem::is_regular_file(model_path) && model_path.extension() == ".onnx"
            ? model_path
            : directory / kModelFileName;
    if (!std::filesystem::is_regular_file(model)) {
        *error = "segmentation bundle is missing model.onnx";
        return false;
    }

    *out_params = ModelParams{};
    out_params->labels = derive_labels(directory / kConfigFileName);
    apply_preprocessor(directory / kPreprocessorFileName, out_params);
    *out_model = model;
    return true;
}

bool load_bundle(const std::filesystem::path& model_path, std::filesystem::path* out_model,
                 ModelParams* out_params, std::string* error) {
    try {
        return load_bundle_impl(model_path, out_model, out_params, error);
    } catch (const std::bad_alloc&) {
        throw;
    } catch (const std::exception& exception) {
        if (error) {
            *error = std::string("invalid segmentation bundle: ") + exception.what();
        }
        return false;
    } catch (...) {
        if (error) {
            *error = "invalid segmentation bundle";
        }
        return false;
    }
}

ResampleCoefficients make_bilinear_coefficients(size_t input_size, size_t output_size) {
    ResampleCoefficients result;
    const double scale = static_cast<double>(input_size) / static_cast<double>(output_size);
    const double filter_scale = std::max(scale, 1.0);
    const double support = filter_scale;
    result.stride = static_cast<size_t>(std::ceil(support)) * 2 + 1;
    result.starts.resize(output_size);
    result.counts.resize(output_size);
    result.values.assign(output_size * result.stride, 0);

    for (size_t output = 0; output < output_size; ++output) {
        const double center = (static_cast<double>(output) + 0.5) * scale;
        size_t first = static_cast<size_t>(std::max(0.0, center - support + 0.5));
        size_t last = static_cast<size_t>(std::max(0.0, center + support + 0.5));
        last = std::min(last, input_size);
        const size_t count = last - first;
        result.starts[output] = first;
        result.counts[output] = count;

        double weight_sum = 0.0;
        std::vector<double> weights(count);
        for (size_t i = 0; i < count; ++i) {
            const double distance =
                std::abs((static_cast<double>(i + first) - center + 0.5) / filter_scale);
            weights[i] = distance < 1.0 ? 1.0 - distance : 0.0;
            weight_sum += weights[i];
        }
        for (size_t i = 0; i < count; ++i) {
            const double normalized = weight_sum == 0.0 ? 0.0 : weights[i] / weight_sum;
            result.values[output * result.stride + i] =
                static_cast<int32_t>(normalized * static_cast<double>(1 << kCoefficientBits) + 0.5);
        }
    }
    return result;
}

uint8_t source_channel(const rac_segmentation_image_t& image, size_t x, size_t y, size_t channel) {
    const size_t pixel_width = image.pixel_format == RAC_SEGMENTATION_PIXEL_FORMAT_RGB8 ? 3 : 4;
    const uint8_t* pixel = image.data + y * image.stride_bytes + x * pixel_width;
    if (image.pixel_format == RAC_SEGMENTATION_PIXEL_FORMAT_BGRA8) {
        return pixel[channel == 0 ? 2 : (channel == 2 ? 0 : 1)];
    }
    return pixel[channel];
}

std::vector<uint8_t> resize_pillow_bilinear_rgb(const rac_segmentation_image_t& image,
                                                size_t input_width, size_t input_height) {
    const auto horizontal = make_bilinear_coefficients(image.width, input_width);
    const auto vertical = make_bilinear_coefficients(image.height, input_height);
    std::vector<uint8_t> intermediate(image.height * input_width * 3);
    std::vector<uint8_t> resized(input_height * input_width * 3);
    constexpr int64_t kRound = 1LL << (kCoefficientBits - 1);

    for (size_t y = 0; y < image.height; ++y) {
        for (size_t x = 0; x < input_width; ++x) {
            const size_t start = horizontal.starts[x];
            const size_t count = horizontal.counts[x];
            for (size_t channel = 0; channel < 3; ++channel) {
                int64_t sum = kRound;
                for (size_t i = 0; i < count; ++i) {
                    sum += static_cast<int64_t>(source_channel(image, start + i, y, channel)) *
                           horizontal.values[x * horizontal.stride + i];
                }
                intermediate[(y * input_width + x) * 3 + channel] =
                    static_cast<uint8_t>(std::clamp<int64_t>(sum >> kCoefficientBits, 0, 255));
            }
        }
    }
    for (size_t y = 0; y < input_height; ++y) {
        const size_t start = vertical.starts[y];
        const size_t count = vertical.counts[y];
        for (size_t x = 0; x < input_width; ++x) {
            for (size_t channel = 0; channel < 3; ++channel) {
                int64_t sum = kRound;
                for (size_t i = 0; i < count; ++i) {
                    sum += static_cast<int64_t>(
                               intermediate[((start + i) * input_width + x) * 3 + channel]) *
                           vertical.values[y * vertical.stride + i];
                }
                resized[(y * input_width + x) * 3 + channel] =
                    static_cast<uint8_t>(std::clamp<int64_t>(sum >> kCoefficientBits, 0, 255));
            }
        }
    }
    return resized;
}

std::vector<float> normalize_nchw(const std::vector<uint8_t>& rgb, const ModelParams& params) {
    const size_t plane = params.input_width * params.input_height;
    std::vector<float> result(plane * 3);
    for (size_t pixel = 0; pixel < plane; ++pixel) {
        for (size_t channel = 0; channel < 3; ++channel) {
            float value = static_cast<float>(rgb[pixel * 3 + channel]);
            if (params.do_rescale) {
                value *= params.rescale;
            }
            if (params.do_normalize) {
                value = (value - params.mean[channel]) / params.stddev[channel];
            }
            result[channel * plane + pixel] = value;
        }
    }
    return result;
}

std::array<uint8_t, 4> diagnostic_color(uint16_t class_id) {
    uint8_t red = 0;
    uint8_t green = 0;
    uint8_t blue = 0;
    uint32_t value = class_id;
    for (uint32_t bit = 0; bit < 8; ++bit) {
        red |= static_cast<uint8_t>((value & 1U) << (7U - bit));
        green |= static_cast<uint8_t>(((value >> 1U) & 1U) << (7U - bit));
        blue |= static_cast<uint8_t>(((value >> 2U) & 1U) << (7U - bit));
        value >>= 3U;
    }
    return {red, green, blue, 255};
}

char* duplicate_string(const std::string& value) {
    char* copy = static_cast<char*>(std::malloc(value.size() + 1));
    if (copy) {
        std::memcpy(copy, value.c_str(), value.size() + 1);
    }
    return copy;
}

std::string label_for(const ModelParams& params, size_t class_id) {
    if (class_id < params.labels.size()) {
        return params.labels[class_id];
    }
    return "class_" + std::to_string(class_id);
}

}  // namespace

class ONNXSegmentationProvider::Impl {
   public:
    std::unique_ptr<Session> session;
    ModelParams params;
    mutable std::mutex mutex;
};

ONNXSegmentationProvider::ONNXSegmentationProvider() : impl_(std::make_unique<Impl>()) {}
ONNXSegmentationProvider::~ONNXSegmentationProvider() = default;

rac_result_t ONNXSegmentationProvider::initialize(const std::string& model_path) {
    try {
        std::filesystem::path model;
        ModelParams params;
        std::string error;
        if (!load_bundle(model_path, &model, &params, &error)) {
            RAC_LOG_ERROR(kLogCategory, "segmentation bundle rejected: %s", error.c_str());
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }

        SessionOptions options;
        options.log_id = "RunAnywhereSegmentation";
        auto session = Session::create(model.string(), options, &error);
        if (!session) {
            RAC_LOG_ERROR(kLogCategory, "segmentation ORT session creation failed: %s",
                          error.c_str());
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }

        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->session = std::move(session);
        impl_->params = std::move(params);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "segmentation bundle rejected: %s", exception.what());
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    } catch (...) {
        RAC_LOG_ERROR(kLogCategory, "segmentation bundle rejected by an unknown validation error");
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

rac_result_t ONNXSegmentationProvider::segment(const rac_segmentation_image_t& image,
                                               const rac_segmentation_options_t& options,
                                               rac_segmentation_result_t* out_result) {
    if (!out_result || !image.data || image.width == 0 || image.height == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_result = {};
    const size_t channels = image.pixel_format == RAC_SEGMENTATION_PIXEL_FORMAT_RGB8 ? 3 : 4;
    if ((image.pixel_format != RAC_SEGMENTATION_PIXEL_FORMAT_RGB8 &&
         image.pixel_format != RAC_SEGMENTATION_PIXEL_FORMAT_RGBA8 &&
         image.pixel_format != RAC_SEGMENTATION_PIXEL_FORMAT_BGRA8) ||
        image.stride_bytes != static_cast<size_t>(image.width) * channels) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    size_t expected_bytes = 0;
    if (!checked_mul(image.stride_bytes, image.height, &expected_bytes) ||
        image.data_size != expected_bytes) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    size_t pixel_count = 0;
    if (image.width > kMaxSourceDimension || image.height > kMaxSourceDimension ||
        !checked_mul(image.width, image.height, &pixel_count) || pixel_count > 4096ULL * 4096ULL) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->session) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    const ModelParams& params = impl_->params;

    const auto started = std::chrono::steady_clock::now();
    std::vector<float> input;
    try {
        input = normalize_nchw(resize_pillow_bilinear_rgb(image, params.input_width,
                                                          params.input_height),
                               params);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const int64_t input_shape[] = {1, 3, static_cast<int64_t>(params.input_height),
                                   static_cast<int64_t>(params.input_width)};
    const TensorInput tensor = {
        .name = "pixel_values",
        .data = input.data(),
        .data_bytes = input.size() * sizeof(float),
        .shape = input_shape,
        .rank = 4,
        .type = ElementType::Float32,
    };
    const char* output_names[] = {"logits"};
    std::vector<TensorOutput> outputs;
    std::string error;
    rac_result_t rc = impl_->session->run(&tensor, 1, output_names, 1, outputs, &error);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(kLogCategory, "segmentation inference failed: %s", error.c_str());
        return rc;
    }
    // Logits are a rank-4 float tensor {1, num_classes, H, W}; all dims are read
    // from the model output rather than pinned to any one architecture.
    if (outputs.size() != 1 || outputs[0].dtype != ElementType::Float32 ||
        outputs[0].shape.size() != 4 || outputs[0].shape[0] != 1 || outputs[0].shape[1] <= 0 ||
        outputs[0].shape[2] <= 0 || outputs[0].shape[3] <= 0 ||
        static_cast<uint64_t>(outputs[0].shape[1]) > kMaxClassCount) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    const size_t class_count = static_cast<size_t>(outputs[0].shape[1]);
    const size_t logits_height = static_cast<size_t>(outputs[0].shape[2]);
    const size_t logits_width = static_cast<size_t>(outputs[0].shape[3]);
    const size_t logits_plane = logits_width * logits_height;
    const size_t expected_logits = class_count * logits_plane;
    if (outputs[0].bytes.size() != expected_logits * sizeof(float)) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    const auto logit_at = [&outputs](size_t index) {
        float value = 0.0f;
        std::memcpy(&value, outputs[0].bytes.data() + index * sizeof(float), sizeof(float));
        return value;
    };
    for (size_t index = 0; index < expected_logits; ++index) {
        if (!std::isfinite(logit_at(index))) {
            RAC_LOG_ERROR(kLogCategory, "segmentation output contains a nonfinite logit");
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }
    }

    out_result->width = image.width;
    out_result->height = image.height;
    out_result->class_mask_count = pixel_count;
    out_result->class_mask = static_cast<uint16_t*>(std::malloc(pixel_count * sizeof(uint16_t)));
    if (!out_result->class_mask) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::vector<uint64_t> counts(class_count, 0);
    const size_t max_y = logits_height - 1;
    const size_t max_x = logits_width - 1;
    for (size_t y = 0; y < image.height; ++y) {
        const float source_y = (static_cast<float>(y) + 0.5f) * (static_cast<float>(logits_height) /
                                                                 static_cast<float>(image.height)) -
                               0.5f;
        const int raw_y0 = static_cast<int>(std::floor(source_y));
        const float wy = source_y - static_cast<float>(raw_y0);
        const size_t y0 = static_cast<size_t>(std::clamp<int>(raw_y0, 0, static_cast<int>(max_y)));
        const size_t y1 =
            static_cast<size_t>(std::clamp<int>(raw_y0 + 1, 0, static_cast<int>(max_y)));
        for (size_t x = 0; x < image.width; ++x) {
            const float source_x =
                (static_cast<float>(x) + 0.5f) *
                    (static_cast<float>(logits_width) / static_cast<float>(image.width)) -
                0.5f;
            const int raw_x0 = static_cast<int>(std::floor(source_x));
            const float wx = source_x - static_cast<float>(raw_x0);
            const size_t x0 =
                static_cast<size_t>(std::clamp<int>(raw_x0, 0, static_cast<int>(max_x)));
            const size_t x1 =
                static_cast<size_t>(std::clamp<int>(raw_x0 + 1, 0, static_cast<int>(max_x)));

            uint16_t best_class = 0;
            float best_value = -std::numeric_limits<float>::infinity();
            for (size_t class_id = 0; class_id < class_count; ++class_id) {
                const size_t plane = class_id * logits_plane;
                const float top = logit_at(plane + y0 * logits_width + x0) * (1.0f - wx) +
                                  logit_at(plane + y0 * logits_width + x1) * wx;
                const float bottom = logit_at(plane + y1 * logits_width + x0) * (1.0f - wx) +
                                     logit_at(plane + y1 * logits_width + x1) * wx;
                const float value = top * (1.0f - wy) + bottom * wy;
                if (value > best_value) {
                    best_value = value;
                    best_class = static_cast<uint16_t>(class_id);
                }
            }
            out_result->class_mask[y * image.width + x] = best_class;
            ++counts[best_class];
        }
    }

    if (options.include_diagnostic_rgba == RAC_TRUE) {
        if (!checked_mul(pixel_count, 4, &out_result->diagnostic_rgba_size)) {
            rac_segmentation_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        out_result->diagnostic_rgba =
            static_cast<uint8_t*>(std::malloc(out_result->diagnostic_rgba_size));
        if (!out_result->diagnostic_rgba) {
            rac_segmentation_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        for (size_t i = 0; i < pixel_count; ++i) {
            const auto color = diagnostic_color(out_result->class_mask[i]);
            std::memcpy(out_result->diagnostic_rgba + i * 4, color.data(), color.size());
        }
    }

    size_t present_classes = 0;
    for (const uint64_t count : counts) {
        present_classes += count > 0 ? 1 : 0;
    }
    out_result->class_summaries = static_cast<rac_segmentation_class_summary_t*>(
        std::calloc(present_classes, sizeof(rac_segmentation_class_summary_t)));
    if (present_classes > 0 && !out_result->class_summaries) {
        rac_segmentation_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->class_summary_count = present_classes;
    size_t summary_index = 0;
    for (size_t class_id = 0; class_id < class_count; ++class_id) {
        if (counts[class_id] == 0) {
            continue;
        }
        auto& summary = out_result->class_summaries[summary_index++];
        summary.class_id = static_cast<uint32_t>(class_id);
        summary.pixel_count = counts[class_id];
        summary.fraction = static_cast<float>(static_cast<double>(counts[class_id]) /
                                              static_cast<double>(pixel_count));
        summary.label = duplicate_string(label_for(params, class_id));
        if (!summary.label) {
            rac_segmentation_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    out_result->processing_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                         std::chrono::steady_clock::now() - started)
                                         .count();
    return RAC_SUCCESS;
}

void ONNXSegmentationProvider::cleanup() {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->session.reset();
    impl_->params = ModelParams{};
}

bool ONNXSegmentationProvider::is_ready() const {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    return impl_->session != nullptr;
}

}  // namespace runanywhere::segmentation
