/** @file onnx_segmentation_provider.cpp @brief Exact SegFormer B0 ONNX pipeline. */

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
#include "rac/foundation/rac_sha256.h"

namespace runanywhere::segmentation {
namespace {

using json = nlohmann::json;
using runanywhere::runtime::onnxrt::ElementType;
using runanywhere::runtime::onnxrt::Session;
using runanywhere::runtime::onnxrt::SessionOptions;
using runanywhere::runtime::onnxrt::TensorInput;
using runanywhere::runtime::onnxrt::TensorOutput;

constexpr const char* kLogCategory = "Segmentation.ONNX";
constexpr const char* kBundleManifestName = "runanywhere-segmentation.json";
constexpr const char* kModelFileName = "model.onnx";
constexpr const char* kConfigFileName = "config.json";
constexpr const char* kPreprocessorFileName = "preprocessor_config.json";
constexpr const char* kArchitecture = "SegformerForSemanticSegmentation";
#if defined(RAC_SEGMENTATION_TEST_FIXTURE_BUNDLE)
constexpr const char* kContract = "segformer-tiny-test-fp32-v1";
constexpr const char* kSourceRepo = "runanywhere/test-segformer-tiny";
constexpr const char* kSourceRevision =
    "41fcc8f1b6d509a90b825dc52dcbad501c40b9a5d68ac1dee03997f9c9dabcb0";
constexpr const char* kUpstreamRepo = "runanywhere/test-segformer-tiny";
constexpr const char* kModelSha256 =
    "41fcc8f1b6d509a90b825dc52dcbad501c40b9a5d68ac1dee03997f9c9dabcb0";
constexpr const char* kConfigSha256 =
    "7fceaae0cbb0910bdfd3bc48b6e4eff773b7b1ef66d731f81c89dbfcc1819818";
constexpr const char* kPreprocessorSha256 =
    "b1aac9a509a8c05ec544d8d008c2074776dce39dbd3b82c84e76550b5621f61c";
constexpr uintmax_t kModelSize = 1027;
constexpr uintmax_t kConfigSize = 3546;
constexpr uintmax_t kPreprocessorSize = 290;
#else
constexpr const char* kContract = "segformer-b0-ade20k-fp32-v1";
constexpr const char* kSourceRepo = "optimum/segformer-b0-finetuned-ade-512-512";
constexpr const char* kSourceRevision = "bc01a2c52665fff5002aa58ec18381ae7444b4f2";
constexpr const char* kUpstreamRepo = "nvidia/segformer-b0-finetuned-ade-512-512";
constexpr const char* kModelSha256 =
    "3a89102115fe3c16230502437b894844ba50cde6f7c800f9884e87c360bcbfc9";
constexpr const char* kConfigSha256 =
    "8faac3a12302746f63d8a3a8c0bbf7f7f49bf459e5a3533bf71c067cb824e799";
constexpr const char* kPreprocessorSha256 =
    "b5fa2a5da2f4483d6f2f8ac96c2a81ff91a91a0815cfbc77cc2ab30fd7c7b45b";
constexpr uintmax_t kModelSize = 15142812;
constexpr uintmax_t kConfigSize = 6980;
constexpr uintmax_t kPreprocessorSize = 428;
#endif
constexpr size_t kInputWidth = 512;
constexpr size_t kInputHeight = 512;
constexpr size_t kClassCount = 150;
constexpr size_t kLogitsWidth = 128;
constexpr size_t kLogitsHeight = 128;
constexpr size_t kMaxSourceDimension = 4096;
constexpr int kCoefficientBits = 22;

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

bool sha256_file(const std::filesystem::path& path, std::string* out) {
    if (!out) {
        return false;
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return false;
    }
    runanywhere::sha256_ctx context;
    runanywhere::sha256_init(&context);
    std::array<uint8_t, 64 * 1024> buffer{};
    while (stream) {
        stream.read(reinterpret_cast<char*>(buffer.data()), buffer.size());
        const auto count = stream.gcount();
        if (count > 0) {
            runanywhere::sha256_update(&context, buffer.data(), static_cast<size_t>(count));
        }
    }
    if (!stream.eof()) {
        return false;
    }
    uint8_t digest[32] = {};
    runanywhere::sha256_final(&context, digest);
    *out = runanywhere::bytes_to_hex(digest, sizeof(digest));
    return true;
}

bool exact_number_array(const json& value, const std::array<double, 3>& expected) {
    if (!value.is_array() || value.size() != expected.size()) {
        return false;
    }
    for (size_t i = 0; i < expected.size(); ++i) {
        if (!value[i].is_number() || std::abs(value[i].get<double>() - expected[i]) > 1e-9) {
            return false;
        }
    }
    return true;
}

bool exact_shape(const json& value, const std::array<int64_t, 4>& expected) {
    if (!value.is_array() || value.size() != expected.size()) {
        return false;
    }
    for (size_t i = 0; i < expected.size(); ++i) {
        if (!value[i].is_number_integer() || value[i].get<int64_t>() != expected[i]) {
            return false;
        }
    }
    return true;
}

bool validate_hash(const std::filesystem::path& path, const json& manifest, const char* field_name,
                   const char* expected, std::string* error) {
    const auto it = manifest.find(field_name);
    if (it == manifest.end() || !it->is_string() ||
        it->get_ref<const std::string&>().size() != 64) {
        *error = std::string("missing or invalid ") + field_name;
        return false;
    }
    std::string actual;
    if (!sha256_file(path, &actual)) {
        *error = std::string("cannot hash ") + path.filename().string();
        return false;
    }
    if (it->get_ref<const std::string&>() != expected || actual != expected) {
        *error = path.filename().string() + " checksum does not match bundle manifest";
        return false;
    }
    return true;
}

bool load_and_validate_bundle_impl(const std::filesystem::path& directory,
                                   std::filesystem::path* out_model,
                                   std::vector<std::string>* out_labels, std::string* error) {
    if (!out_model || !out_labels || !error) {
        return false;
    }
    const auto manifest_path = directory / kBundleManifestName;
    const auto model_path = directory / kModelFileName;
    const auto config_path = directory / kConfigFileName;
    const auto preprocessor_path = directory / kPreprocessorFileName;

    if (!std::filesystem::is_regular_file(manifest_path) ||
        !std::filesystem::is_regular_file(model_path) ||
        !std::filesystem::is_regular_file(config_path) ||
        !std::filesystem::is_regular_file(preprocessor_path) ||
        std::filesystem::file_size(manifest_path) > 64 * 1024 ||
        std::filesystem::file_size(model_path) != kModelSize ||
        std::filesystem::file_size(config_path) != kConfigSize ||
        std::filesystem::file_size(preprocessor_path) != kPreprocessorSize) {
        *error =
            "bundle requires model.onnx, config.json, preprocessor_config.json, and "
            "runanywhere-segmentation.json with the exact pinned byte sizes";
        return false;
    }

    std::string manifest_bytes;
    std::string config_bytes;
    std::string preprocessor_bytes;
    if (!read_file(manifest_path, &manifest_bytes) || !read_file(config_path, &config_bytes) ||
        !read_file(preprocessor_path, &preprocessor_bytes)) {
        *error = "cannot read the pinned segmentation bundle";
        return false;
    }

    json manifest;
    json config;
    json preprocessor;
    try {
        manifest = json::parse(manifest_bytes);
        config = json::parse(config_bytes);
        preprocessor = json::parse(preprocessor_bytes);
    } catch (const std::exception& exception) {
        *error = std::string("invalid segmentation JSON sidecar: ") + exception.what();
        return false;
    }

    const bool manifest_identity =
        manifest.value("schema_version", 0) == 1 &&
        manifest.value("contract", std::string()) == kContract &&
        manifest.value("architecture", std::string()) == kArchitecture &&
        manifest.value("model_file", std::string()) == kModelFileName &&
        manifest.value("source_repo", std::string()) == kSourceRepo &&
        manifest.value("source_revision", std::string()) == kSourceRevision &&
        manifest.value("upstream_repo", std::string()) == kUpstreamRepo &&
        manifest.value("model_size", uintmax_t{0}) == kModelSize &&
        manifest.value("config_size", uintmax_t{0}) == kConfigSize &&
        manifest.value("preprocessor_config_size", uintmax_t{0}) == kPreprocessorSize &&
        manifest.contains("input") && manifest["input"].is_object() &&
        manifest["input"].value("name", std::string()) == "pixel_values" &&
        manifest["input"].value("dtype", std::string()) == "float32" &&
        exact_shape(manifest["input"].value("shape", json::array()), {1, 3, 512, 512}) &&
        manifest.contains("output") && manifest["output"].is_object() &&
        manifest["output"].value("name", std::string()) == "logits" &&
        manifest["output"].value("dtype", std::string()) == "float32" &&
        exact_shape(manifest["output"].value("shape", json::array()), {1, 150, 128, 128});
    if (!manifest_identity) {
        *error = "bundle manifest does not identify the exact SegFormer FP32 contract";
        return false;
    }
    if (!validate_hash(model_path, manifest, "model_sha256", kModelSha256, error) ||
        !validate_hash(config_path, manifest, "config_sha256", kConfigSha256, error) ||
        !validate_hash(preprocessor_path, manifest, "preprocessor_config_sha256",
                       kPreprocessorSha256, error)) {
        return false;
    }

    const bool config_identity =
        config.value("model_type", std::string()) == "segformer" &&
        config.value("num_channels", 0) == 3 &&
        config.value("torch_dtype", std::string()) == "float32" &&
        config.contains("architectures") && config["architectures"].is_array() &&
        std::find(config["architectures"].begin(), config["architectures"].end(), kArchitecture) !=
            config["architectures"].end() &&
        config.contains("id2label") && config["id2label"].is_object() &&
        config["id2label"].size() == kClassCount;
    if (!config_identity) {
        *error = "config.json is not the expected 150-class FP32 SegFormer architecture";
        return false;
    }

    out_labels->clear();
    out_labels->reserve(kClassCount);
    for (size_t i = 0; i < kClassCount; ++i) {
        const auto key = std::to_string(i);
        const auto it = config["id2label"].find(key);
        if (it == config["id2label"].end() || !it->is_string()) {
            *error = "config.json id2label must contain string labels 0 through 149";
            return false;
        }
        out_labels->push_back(it->get<std::string>());
    }

    const bool preprocessor_identity =
        preprocessor.value("do_normalize", false) && preprocessor.value("do_rescale", false) &&
        preprocessor.value("do_resize", false) && preprocessor.value("resample", -1) == 2 &&
        preprocessor.contains("size") && preprocessor["size"].is_object() &&
        preprocessor["size"].value("width", 0) == static_cast<int>(kInputWidth) &&
        preprocessor["size"].value("height", 0) == static_cast<int>(kInputHeight) &&
        std::abs(preprocessor.value("rescale_factor", 0.0) - (1.0 / 255.0)) < 1e-12 &&
        exact_number_array(preprocessor.value("image_mean", json::array()),
                           {0.485, 0.456, 0.406}) &&
        exact_number_array(preprocessor.value("image_std", json::array()), {0.229, 0.224, 0.225});
    if (!preprocessor_identity) {
        *error =
            "preprocessor_config.json is not the exact 512px Pillow-bilinear/ImageNet contract";
        return false;
    }

    *out_model = model_path;
    return true;
}

bool load_and_validate_bundle(const std::filesystem::path& directory,
                              std::filesystem::path* out_model,
                              std::vector<std::string>* out_labels, std::string* error) {
    try {
        return load_and_validate_bundle_impl(directory, out_model, out_labels, error);
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

std::vector<uint8_t> resize_pillow_bilinear_rgb(const rac_segmentation_image_t& image) {
    const auto horizontal = make_bilinear_coefficients(image.width, kInputWidth);
    const auto vertical = make_bilinear_coefficients(image.height, kInputHeight);
    std::vector<uint8_t> intermediate(image.height * kInputWidth * 3);
    std::vector<uint8_t> resized(kInputHeight * kInputWidth * 3);
    constexpr int64_t kRound = 1LL << (kCoefficientBits - 1);

    for (size_t y = 0; y < image.height; ++y) {
        for (size_t x = 0; x < kInputWidth; ++x) {
            const size_t start = horizontal.starts[x];
            const size_t count = horizontal.counts[x];
            for (size_t channel = 0; channel < 3; ++channel) {
                int64_t sum = kRound;
                for (size_t i = 0; i < count; ++i) {
                    sum += static_cast<int64_t>(source_channel(image, start + i, y, channel)) *
                           horizontal.values[x * horizontal.stride + i];
                }
                intermediate[(y * kInputWidth + x) * 3 + channel] =
                    static_cast<uint8_t>(std::clamp<int64_t>(sum >> kCoefficientBits, 0, 255));
            }
        }
    }
    for (size_t y = 0; y < kInputHeight; ++y) {
        const size_t start = vertical.starts[y];
        const size_t count = vertical.counts[y];
        for (size_t x = 0; x < kInputWidth; ++x) {
            for (size_t channel = 0; channel < 3; ++channel) {
                int64_t sum = kRound;
                for (size_t i = 0; i < count; ++i) {
                    sum += static_cast<int64_t>(
                               intermediate[((start + i) * kInputWidth + x) * 3 + channel]) *
                           vertical.values[y * vertical.stride + i];
                }
                resized[(y * kInputWidth + x) * 3 + channel] =
                    static_cast<uint8_t>(std::clamp<int64_t>(sum >> kCoefficientBits, 0, 255));
            }
        }
    }
    return resized;
}

std::vector<float> normalize_nchw(const std::vector<uint8_t>& rgb) {
    constexpr std::array<float, 3> kMean = {0.485f, 0.456f, 0.406f};
    constexpr std::array<float, 3> kStd = {0.229f, 0.224f, 0.225f};
    const size_t plane = kInputWidth * kInputHeight;
    std::vector<float> result(plane * 3);
    for (size_t pixel = 0; pixel < plane; ++pixel) {
        for (size_t channel = 0; channel < 3; ++channel) {
            const float rescaled = static_cast<float>(rgb[pixel * 3 + channel]) / 255.0f;
            result[channel * plane + pixel] = (rescaled - kMean[channel]) / kStd[channel];
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

}  // namespace

class ONNXSegmentationProvider::Impl {
   public:
    std::unique_ptr<Session> session;
    std::vector<std::string> labels;
    mutable std::mutex mutex;
};

ONNXSegmentationProvider::ONNXSegmentationProvider() : impl_(std::make_unique<Impl>()) {}
ONNXSegmentationProvider::~ONNXSegmentationProvider() = default;

rac_result_t ONNXSegmentationProvider::initialize(const std::string& model_path) {
    try {
        std::filesystem::path supplied(model_path);
        std::filesystem::path directory =
            std::filesystem::is_directory(supplied) ? supplied : supplied.parent_path();
        if (directory.empty()) {
            directory = ".";
        }

        std::filesystem::path model;
        std::vector<std::string> labels;
        std::string error;
        if (!load_and_validate_bundle(directory, &model, &labels, &error)) {
            RAC_LOG_ERROR(kLogCategory, "SegFormer bundle rejected: %s", error.c_str());
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }

        SessionOptions options;
        options.log_id = "RunAnywhereSegFormer";
        auto session = Session::create(model.string(), options, &error);
        if (!session) {
            RAC_LOG_ERROR(kLogCategory, "SegFormer ORT session creation failed: %s", error.c_str());
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }

        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->session = std::move(session);
        impl_->labels = std::move(labels);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "SegFormer bundle rejected: %s", exception.what());
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    } catch (...) {
        RAC_LOG_ERROR(kLogCategory, "SegFormer bundle rejected by an unknown validation error");
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
    if (!impl_->session || impl_->labels.size() != kClassCount) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    const auto started = std::chrono::steady_clock::now();
    std::vector<float> input;
    try {
        input = normalize_nchw(resize_pillow_bilinear_rgb(image));
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const int64_t input_shape[] = {1, 3, 512, 512};
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
        RAC_LOG_ERROR(kLogCategory, "SegFormer inference failed: %s", error.c_str());
        return rc;
    }
    const std::vector<int64_t> expected_shape = {1, 150, 128, 128};
    size_t expected_logits_bytes = kClassCount * kLogitsWidth * kLogitsHeight * sizeof(float);
    if (outputs.size() != 1 || outputs[0].dtype != ElementType::Float32 ||
        outputs[0].shape != expected_shape || outputs[0].bytes.size() != expected_logits_bytes) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    const auto logit_at = [&outputs](size_t index) {
        float value = 0.0f;
        std::memcpy(&value, outputs[0].bytes.data() + index * sizeof(float), sizeof(float));
        return value;
    };
    for (size_t index = 0; index < expected_logits_bytes / sizeof(float); ++index) {
        if (!std::isfinite(logit_at(index))) {
            RAC_LOG_ERROR(kLogCategory, "SegFormer output contains a nonfinite logit");
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
    std::array<uint64_t, kClassCount> counts{};
    constexpr size_t kLogitsPlane = kLogitsWidth * kLogitsHeight;
    for (size_t y = 0; y < image.height; ++y) {
        const float source_y = (static_cast<float>(y) + 0.5f) * (static_cast<float>(kLogitsHeight) /
                                                                 static_cast<float>(image.height)) -
                               0.5f;
        const int raw_y0 = static_cast<int>(std::floor(source_y));
        const float wy = source_y - static_cast<float>(raw_y0);
        const size_t y0 = static_cast<size_t>(std::clamp(raw_y0, 0, 127));
        const size_t y1 = static_cast<size_t>(std::clamp(raw_y0 + 1, 0, 127));
        for (size_t x = 0; x < image.width; ++x) {
            const float source_x =
                (static_cast<float>(x) + 0.5f) *
                    (static_cast<float>(kLogitsWidth) / static_cast<float>(image.width)) -
                0.5f;
            const int raw_x0 = static_cast<int>(std::floor(source_x));
            const float wx = source_x - static_cast<float>(raw_x0);
            const size_t x0 = static_cast<size_t>(std::clamp(raw_x0, 0, 127));
            const size_t x1 = static_cast<size_t>(std::clamp(raw_x0 + 1, 0, 127));

            uint16_t best_class = 0;
            float best_value = -std::numeric_limits<float>::infinity();
            for (size_t class_id = 0; class_id < kClassCount; ++class_id) {
                const size_t plane = class_id * kLogitsPlane;
                const float top = logit_at(plane + y0 * kLogitsWidth + x0) * (1.0f - wx) +
                                  logit_at(plane + y0 * kLogitsWidth + x1) * wx;
                const float bottom = logit_at(plane + y1 * kLogitsWidth + x0) * (1.0f - wx) +
                                     logit_at(plane + y1 * kLogitsWidth + x1) * wx;
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
    for (size_t class_id = 0; class_id < kClassCount; ++class_id) {
        if (counts[class_id] == 0) {
            continue;
        }
        auto& summary = out_result->class_summaries[summary_index++];
        summary.class_id = static_cast<uint32_t>(class_id);
        summary.pixel_count = counts[class_id];
        summary.fraction = static_cast<float>(static_cast<double>(counts[class_id]) /
                                              static_cast<double>(pixel_count));
        summary.label = duplicate_string(impl_->labels[class_id]);
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
    impl_->labels.clear();
}

bool ONNXSegmentationProvider::is_ready() const {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    return impl_->session != nullptr;
}

}  // namespace runanywhere::segmentation
