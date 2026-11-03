/**
 * @file test_segmentation_confidence.cpp
 * @brief Contract test for malformed segmentation confidence payloads.
 *
 * Backend-neutral: an in-test fake segmentation engine supplies the payloads,
 * so no ONNX session, model file, or backend library is needed. The test pins
 * the two entry points introduced with the confidence extension:
 *
 *   - the direct path (rac_segmentation_segment_with_confidence)
 *   - the proto path (rac_segmentation_component_segment_proto)
 *
 * Both must reject a wrong-sized/null confidence mask with
 * RAC_ERROR_ENCODING_ERROR and must release every output they allocated. The
 * proto path additionally rejects a diagnostic buffer that is present when it
 * was not requested (and absent when it was), plus malformed class masks and
 * class summaries.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/segmentation/rac_segmentation_component.h"
#include "rac/features/segmentation/rac_segmentation_confidence.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "segmentation.pb.h"
#endif

namespace {

int g_failures = 0;

void check(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++g_failures;
    }
}

constexpr uint32_t kWidth = 6;
constexpr uint32_t kHeight = 4;
constexpr size_t kPixels = static_cast<size_t>(kWidth) * kHeight;

enum class PayloadMode {
    kValid,
    kConfidenceNull,
    kConfidenceShort,
    kConfidenceLong,
    kConfidenceZero,
    kInferenceFailed,
    kConfidenceInferenceFailed,
    kWrongDimensions,
    kShortClassMask,
    kMissingDiagnostic,
    kUnexpectedDiagnostic,
    kSummaryMismatch,
};

PayloadMode g_mode = PayloadMode::kValid;
int g_confidence_calls = 0;
std::vector<uint8_t> g_valid_class_mask;
std::vector<uint8_t> g_valid_diagnostic;
std::vector<uint8_t> g_valid_confidence;

struct FakeSegmentationImpl {
    std::string model_path;
};

rac_result_t fake_create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = new FakeSegmentationImpl{};
    return RAC_SUCCESS;
}

rac_result_t fake_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    static_cast<FakeSegmentationImpl*>(impl)->model_path = model_path;
    return RAC_SUCCESS;
}

rac_result_t fake_segment(void* impl, const rac_segmentation_image_t* image,
                          const rac_segmentation_options_t* options,
                          rac_segmentation_result_t* out_result) {
    if (!impl || !image || !options || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_result = {};
    out_result->width = image->width;
    out_result->height = image->height;
    out_result->processing_time_ms = 1;

    if (g_mode == PayloadMode::kWrongDimensions) {
        out_result->width = image->width + 1;
    }

    out_result->class_mask = static_cast<uint16_t*>(std::malloc(kPixels * sizeof(uint16_t)));
    if (!out_result->class_mask) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->class_mask_count = g_mode == PayloadMode::kShortClassMask ? kPixels - 1 : kPixels;
    for (size_t i = 0; i < kPixels; ++i) {
        out_result->class_mask[i] = static_cast<uint16_t>(i % 3U);
    }

    const bool diagnostic_requested =
        g_mode == PayloadMode::kUnexpectedDiagnostic ||
        (g_mode != PayloadMode::kMissingDiagnostic && options->include_diagnostic_rgba == RAC_TRUE);
    if (diagnostic_requested) {
        out_result->diagnostic_rgba_size = kPixels * 4;
        out_result->diagnostic_rgba =
            static_cast<uint8_t*>(std::malloc(out_result->diagnostic_rgba_size));
        if (!out_result->diagnostic_rgba) {
            rac_segmentation_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        for (size_t i = 0; i < kPixels; ++i) {
            out_result->diagnostic_rgba[i * 4] = 10;
            out_result->diagnostic_rgba[i * 4 + 1] = 20;
            out_result->diagnostic_rgba[i * 4 + 2] = 30;
            out_result->diagnostic_rgba[i * 4 + 3] = 255;
        }
    }

    out_result->class_summary_count = 1;
    out_result->class_summaries = static_cast<rac_segmentation_class_summary_t*>(
        std::calloc(1, sizeof(rac_segmentation_class_summary_t)));
    if (!out_result->class_summaries) {
        rac_segmentation_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    auto& summary = out_result->class_summaries[0];
    summary.class_id = 0;
    if (g_mode == PayloadMode::kSummaryMismatch) {
        summary.pixel_count = kPixels - 1;
        summary.fraction = static_cast<float>(kPixels - 1) / static_cast<float>(kPixels);
    } else {
        summary.pixel_count = kPixels;
        summary.fraction = 1.0f;
    }
    summary.label = strdup("fake");

    if (g_mode == PayloadMode::kInferenceFailed) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
    return RAC_SUCCESS;
}

rac_result_t fake_segment_with_confidence(void* impl, const rac_segmentation_image_t* image,
                                          const rac_segmentation_options_t* options,
                                          rac_segmentation_result_t* out_result,
                                          rac_segmentation_confidence_mask_v1_t* out_confidence) {
    ++g_confidence_calls;
    const rac_result_t rc = fake_segment(impl, image, options, out_result);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!out_confidence) {
        rac_segmentation_result_free(out_result);
        return RAC_ERROR_NULL_POINTER;
    }
    out_confidence->data = static_cast<uint8_t*>(std::malloc(kPixels));
    if (!out_confidence->data) {
        rac_segmentation_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_confidence->size = kPixels;
    for (size_t i = 0; i < kPixels; ++i) {
        out_confidence->data[i] = static_cast<uint8_t>(100 + (i % 5));
    }

    switch (g_mode) {
        case PayloadMode::kConfidenceNull:
            std::free(out_confidence->data);
            out_confidence->data = nullptr;
            break;
        case PayloadMode::kConfidenceShort:
            out_confidence->size = kPixels - 1;
            break;
        case PayloadMode::kConfidenceLong:
            out_confidence->size = kPixels + 1;
            break;
        case PayloadMode::kConfidenceZero:
            out_confidence->size = 0;
            break;
        case PayloadMode::kConfidenceInferenceFailed:
            return RAC_ERROR_INFERENCE_FAILED;
        default:
            break;
    }
    return RAC_SUCCESS;
}

rac_result_t fake_cleanup(void*) {
    return RAC_SUCCESS;
}

void fake_destroy(void* impl) {
    delete static_cast<FakeSegmentationImpl*>(impl);
}

const rac_segmentation_service_ops_t kFakeSegmentationOps = {
    /* initialize */ fake_initialize,
    /* segment     */ fake_segment,
    /* cleanup     */ fake_cleanup,
    /* destroy     */ fake_destroy,
    /* create      */ fake_create,
};

const rac_segmentation_confidence_ops_v1_t kFakeConfidenceOps = {
    /* struct_size */ sizeof(rac_segmentation_confidence_ops_v1_t),
    /* version     */ RAC_SEGMENTATION_CONFIDENCE_VERSION_1,
    /* segment     */ fake_segment_with_confidence,
};

const rac_primitive_t kPrimitives[] = {RAC_PRIMITIVE_SEGMENT};
const uint32_t kFormats[] = {static_cast<uint32_t>(RAC_MODEL_FORMAT_ONNX)};

const rac_engine_manifest_t kLegacyManifest = {
    .name = "fake-segmentation-legacy",
    .display_name = "Fake Segmentation Legacy",
    .version = "1",
    .package_owner = "runanywhere-tests",
    .package_name = "rac_segmentation_confidence_test",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 900,
    .capability_flags = 0,
    .primitives = kPrimitives,
    .primitives_count = sizeof(kPrimitives) / sizeof(kPrimitives[0]),
    .runtimes = nullptr,
    .runtimes_count = 0,
    .formats = kFormats,
    .formats_count = sizeof(kFormats) / sizeof(kFormats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

const rac_segmentation_confidence_manifest_v1_t kConfidenceManifest = {
    .manifest =
        {
            .name = "fake-segmentation-confidence",
            .display_name = "Fake Segmentation Confidence",
            .version = "1",
            .package_owner = "runanywhere-tests",
            .package_name = "rac_segmentation_confidence_test",
            .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
            .priority = 1000,
            .capability_flags = RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1,
            .primitives = kPrimitives,
            .primitives_count = sizeof(kPrimitives) / sizeof(kPrimitives[0]),
            .runtimes = nullptr,
            .runtimes_count = 0,
            .formats = kFormats,
            .formats_count = sizeof(kFormats) / sizeof(kFormats[0]),
            .reserved_0 = 0,
            .reserved_1 = 0,
        },
    .struct_size = sizeof(rac_segmentation_confidence_manifest_v1_t),
    .version = RAC_SEGMENTATION_CONFIDENCE_VERSION_1,
    .confidence_ops = &kFakeConfidenceOps,
};

rac_engine_vtable_t make_vtable(const rac_engine_manifest_t& manifest) {
    rac_engine_vtable_t vtable{};
    vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vtable.metadata.name = manifest.name;
    vtable.metadata.display_name = manifest.display_name;
    vtable.metadata.engine_version = manifest.version;
    vtable.metadata.priority = manifest.priority;
    vtable.metadata.capability_flags = manifest.capability_flags;
    vtable.metadata.runtimes = manifest.runtimes;
    vtable.metadata.runtimes_count = manifest.runtimes_count;
    vtable.metadata.formats = manifest.formats;
    vtable.metadata.formats_count = manifest.formats_count;
    vtable.segmentation_ops = &kFakeSegmentationOps;
    return vtable;
}

std::vector<uint8_t> make_rgb() {
    std::vector<uint8_t> rgb(kPixels * 3, 0x80);
    for (size_t i = 0; i < kPixels; ++i) {
        rgb[i * 3] = static_cast<uint8_t>(i * 7U);
        rgb[i * 3 + 1] = static_cast<uint8_t>(i * 11U + 17U);
        rgb[i * 3 + 2] = static_cast<uint8_t>(i * 13U + 29U);
    }
    return rgb;
}

rac_segmentation_image_t make_image(const std::vector<uint8_t>& rgb) {
    rac_segmentation_image_t image{};
    image.data = rgb.data();
    image.data_size = rgb.size();
    image.width = kWidth;
    image.height = kHeight;
    image.stride_bytes = static_cast<size_t>(kWidth) * 3;
    image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
    return image;
}

bool outputs_cleared(const rac_segmentation_result_t& result,
                     const rac_segmentation_confidence_mask_v1_t& confidence) {
    return result.width == 0 && result.height == 0 && result.class_mask == nullptr &&
           result.class_mask_count == 0 && result.diagnostic_rgba == nullptr &&
           result.diagnostic_rgba_size == 0 && result.class_summaries == nullptr &&
           result.class_summary_count == 0 && confidence.data == nullptr && confidence.size == 0;
}

void check_valid_result(const rac_segmentation_result_t& result,
                        const rac_segmentation_confidence_mask_v1_t& confidence) {
    check(result.width == kWidth && result.height == kHeight && result.class_mask != nullptr &&
              result.class_mask_count == kPixels,
          "valid confidence payload keeps the source-sized class mask");
    check(confidence.data != nullptr && confidence.size == kPixels,
          "valid confidence payload is exactly width * height bytes");
    bool pattern_ok = confidence.data != nullptr;
    for (size_t i = 0; i < kPixels && pattern_ok; ++i) {
        pattern_ok = confidence.data[i] == static_cast<uint8_t>(100 + (i % 5));
    }
    check(pattern_ok, "valid confidence bytes preserve order and values");
    check(result.class_summary_count == 1 && result.class_summaries != nullptr &&
              result.class_summaries[0].pixel_count == kPixels,
          "valid confidence payload keeps a complete class summary");
}

#if defined(RAC_HAVE_PROTOBUF)

std::string make_request(bool include_confidence, bool include_diagnostic) {
    runanywhere::v1::SegmentationRequest request;
    auto* image = request.mutable_image();
    const auto rgb = make_rgb();
    image->set_data(rgb.data(), rgb.size());
    image->set_width(kWidth);
    image->set_height(kHeight);
    image->set_pixel_format(runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8);
    auto* options = request.mutable_options();
    options->set_include_confidence(include_confidence);
    options->set_include_diagnostic_rgba(include_diagnostic);
    return request.SerializeAsString();
}

rac_result_t segment_proto(rac_handle_t component, const std::string& request_bytes,
                           runanywhere::v1::SegmentationResult* out_result) {
    rac_proto_buffer_t buffer{};
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_segmentation_component_segment_proto(
        component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
        &buffer);
    bool parsed = true;
    if (rc == RAC_SUCCESS && out_result) {
        parsed = out_result->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    }
    rac_proto_buffer_free(&buffer);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return parsed ? RAC_SUCCESS : RAC_ERROR_DECODING_ERROR;
}

#endif  // RAC_HAVE_PROTOBUF

void run_entry_validation(rac_handle_t handle, const std::vector<uint8_t>& rgb) {
    const auto image = make_image(rgb);
    rac_segmentation_options_t options = RAC_SEGMENTATION_OPTIONS_DEFAULT;

    int calls_before = g_confidence_calls;
    auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
    rac_segmentation_result_t result{};
    check(rac_segmentation_segment_with_confidence(handle, &image, &options, nullptr,
                                                   &confidence) == RAC_ERROR_NULL_POINTER,
          "null result is rejected");
    check(rac_segmentation_segment_with_confidence(nullptr, &image, &options, &result,
                                                   &confidence) == RAC_ERROR_NULL_POINTER,
          "null handle is rejected");
    auto null_data_image = image;
    null_data_image.data = nullptr;
    check(rac_segmentation_segment_with_confidence(handle, &null_data_image, &options, &result,
                                                   &confidence) == RAC_ERROR_NULL_POINTER,
          "null image data is rejected");
    check(rac_segmentation_segment_with_confidence(handle, &image, &options, &result, nullptr) ==
              RAC_ERROR_NULL_POINTER,
          "null confidence output is rejected");

    rac_segmentation_confidence_mask_v1_t zero_header{};
    check(rac_segmentation_segment_with_confidence(handle, &image, &options, &result,
                                                   &zero_header) == RAC_ERROR_INVALID_PARAMETER,
          "zero confidence header is rejected before dispatch");

    auto non_empty = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
    uint8_t sentinel = 0;
    non_empty.data = &sentinel;
    check(rac_segmentation_segment_with_confidence(handle, &image, &options, &result, &non_empty) ==
              RAC_ERROR_INVALID_PARAMETER,
          "non-empty confidence output is rejected before dispatch");

    auto non_zero_size = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
    non_zero_size.size = 1;
    check(rac_segmentation_segment_with_confidence(handle, &image, &options, &result,
                                                   &non_zero_size) == RAC_ERROR_INVALID_PARAMETER,
          "non-zero confidence size is rejected before dispatch");

    check(g_confidence_calls == calls_before,
          "entry validation rejects before the engine is called");
}

void run_direct_cases(rac_handle_t handle, const std::vector<uint8_t>& rgb) {
    const auto image = make_image(rgb);
    rac_segmentation_options_t options = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    options.include_diagnostic_rgba = RAC_TRUE;

    auto expect_error = [&](PayloadMode mode, rac_result_t expected, const char* label) {
        g_mode = mode;
        rac_segmentation_result_t result{};
        auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
        const rac_result_t rc = rac_segmentation_segment_with_confidence(handle, &image, &options,
                                                                         &result, &confidence);
        check(rc == expected, label);
        check(outputs_cleared(result, confidence),
              "rejected payload releases both outputs and resets them");
        rac_segmentation_confidence_mask_free(&confidence);
        check(confidence.data == nullptr && confidence.size == 0,
              "freeing a reset confidence output is safe");
    };

    g_mode = PayloadMode::kValid;
    {
        rac_segmentation_result_t result{};
        auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
        const rac_result_t rc = rac_segmentation_segment_with_confidence(handle, &image, &options,
                                                                         &result, &confidence);
        check(rc == RAC_SUCCESS, "direct valid payload succeeds");
        check_valid_result(result, confidence);
        if (result.class_mask && result.class_mask_count == kPixels) {
            g_valid_class_mask.resize(kPixels * sizeof(uint16_t));
            for (size_t i = 0; i < kPixels; ++i) {
                const uint16_t value = result.class_mask[i];
                g_valid_class_mask[i * 2] = static_cast<uint8_t>(value & 0xffU);
                g_valid_class_mask[i * 2 + 1] = static_cast<uint8_t>((value >> 8U) & 0xffU);
            }
        }
        if (result.diagnostic_rgba && result.diagnostic_rgba_size > 0) {
            g_valid_diagnostic.assign(result.diagnostic_rgba,
                                      result.diagnostic_rgba + result.diagnostic_rgba_size);
        }
        if (confidence.data && confidence.size > 0) {
            g_valid_confidence.assign(confidence.data, confidence.data + confidence.size);
        }
        rac_segmentation_result_free(&result);
        rac_segmentation_confidence_mask_free(&confidence);
        check(result.class_mask == nullptr && confidence.data == nullptr,
              "public free helpers reset both outputs");
    }

    expect_error(PayloadMode::kConfidenceNull, RAC_ERROR_ENCODING_ERROR,
                 "null confidence bytes are rejected");
    expect_error(PayloadMode::kConfidenceShort, RAC_ERROR_ENCODING_ERROR,
                 "short confidence mask is rejected");
    expect_error(PayloadMode::kConfidenceLong, RAC_ERROR_ENCODING_ERROR,
                 "long confidence mask is rejected");
    expect_error(PayloadMode::kConfidenceZero, RAC_ERROR_ENCODING_ERROR,
                 "zero-length confidence mask is rejected");
    expect_error(PayloadMode::kWrongDimensions, RAC_ERROR_ENCODING_ERROR,
                 "wrong result dimensions are rejected");
    expect_error(PayloadMode::kShortClassMask, RAC_ERROR_ENCODING_ERROR,
                 "short class mask is rejected");

    {
        g_mode = PayloadMode::kInferenceFailed;
        rac_segmentation_result_t result{};
        auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
        const rac_result_t rc = rac_segmentation_segment_with_confidence(handle, &image, &options,
                                                                         &result, &confidence);
        check(rc == RAC_ERROR_INFERENCE_FAILED, "engine failure is returned unchanged");
        check(outputs_cleared(result, confidence),
              "engine failure releases the partial result and confidence outputs");
    }

    {
        g_mode = PayloadMode::kConfidenceInferenceFailed;
        rac_segmentation_result_t result{};
        auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
        const rac_result_t rc = rac_segmentation_segment_with_confidence(handle, &image, &options,
                                                                         &result, &confidence);
        check(rc == RAC_ERROR_INFERENCE_FAILED, "confidence-engine failure is returned unchanged");
        check(outputs_cleared(result, confidence),
              "confidence-engine failure releases both partial outputs");
    }

    g_mode = PayloadMode::kValid;
}

#if defined(RAC_HAVE_PROTOBUF)

void run_proto_cases(rac_handle_t component) {
    {
        const auto request = make_request(true, true);
        runanywhere::v1::SegmentationResult result;
        const rac_result_t rc = segment_proto(component, request, &result);
        check(rc == RAC_SUCCESS, "proto valid confidence request succeeds");
        check(result.width() == kWidth && result.height() == kHeight,
              "proto result keeps the source dimensions");
        check(result.confidence_mask_u8().size() == kPixels,
              "proto confidence mask is exactly width * height bytes");
        bool pattern_ok = result.confidence_mask_u8().size() == kPixels;
        for (size_t i = 0; i < result.confidence_mask_u8().size() && pattern_ok; ++i) {
            pattern_ok = static_cast<uint8_t>(result.confidence_mask_u8()[i]) ==
                         static_cast<uint8_t>(100 + (i % 5));
        }
        check(pattern_ok, "proto confidence bytes preserve order and values");
        check(result.diagnostic_rgba().size() == kPixels * 4,
              "proto diagnostic is present when requested");
        const std::vector<uint8_t> proto_confidence(result.confidence_mask_u8().begin(),
                                                    result.confidence_mask_u8().end());
        const std::vector<uint8_t> proto_class_mask(result.class_mask_u16_le().begin(),
                                                    result.class_mask_u16_le().end());
        const std::vector<uint8_t> proto_diagnostic(result.diagnostic_rgba().begin(),
                                                    result.diagnostic_rgba().end());
        check(proto_confidence == g_valid_confidence,
              "direct and proto paths return identical confidence bytes");
        check(proto_class_mask == g_valid_class_mask,
              "direct and proto paths return identical class-mask bytes");
        check(proto_diagnostic == g_valid_diagnostic,
              "direct and proto paths return identical diagnostic bytes");
    }

    {
        const auto request = make_request(false, false);
        runanywhere::v1::SegmentationResult result;
        const rac_result_t rc = segment_proto(component, request, &result);
        check(rc == RAC_SUCCESS, "proto request without optional outputs succeeds");
        check(result.confidence_mask_u8().empty(),
              "proto confidence is absent when it was not requested");
        check(result.diagnostic_rgba().empty(),
              "proto diagnostic is absent when it was not requested");
    }

    auto expect_error = [&](PayloadMode mode, bool include_confidence, bool include_diagnostic,
                            rac_result_t expected, const char* label) {
        g_mode = mode;
        runanywhere::v1::SegmentationResult result;
        const rac_result_t rc =
            segment_proto(component, make_request(include_confidence, include_diagnostic), &result);
        check(rc == expected, label);
    };

    expect_error(PayloadMode::kConfidenceNull, true, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects a null confidence mask");
    expect_error(PayloadMode::kConfidenceShort, true, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects a short confidence mask");
    expect_error(PayloadMode::kConfidenceLong, true, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects a long confidence mask");
    expect_error(PayloadMode::kMissingDiagnostic, false, true, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects a missing requested diagnostic");
    expect_error(PayloadMode::kUnexpectedDiagnostic, false, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects an unrequested diagnostic");
    expect_error(PayloadMode::kShortClassMask, false, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects a short class mask");
    expect_error(PayloadMode::kWrongDimensions, false, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects wrong result dimensions");
    expect_error(PayloadMode::kSummaryMismatch, false, false, RAC_ERROR_ENCODING_ERROR,
                 "proto rejects class summaries that do not partition the image");
    expect_error(PayloadMode::kInferenceFailed, true, false, RAC_ERROR_INFERENCE_FAILED,
                 "proto returns an engine failure unchanged");

    g_mode = PayloadMode::kValid;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    std::fprintf(stdout, "test_segmentation_confidence\n");

    // (1) An engine without the confidence extension still serves the legacy
    // operation; the opt-in confidence operation reports NOT_SUPPORTED.
    rac_engine_vtable_t legacy_vtable = make_vtable(kLegacyManifest);
    check(rac_engine_manifest_attach_vtable(&kLegacyManifest, &legacy_vtable) == RAC_SUCCESS,
          "legacy manifest matches its vtable");
    check(rac_plugin_register(&legacy_vtable) == RAC_SUCCESS, "legacy engine registers");

    const auto rgb = make_rgb();
    const auto image = make_image(rgb);
    rac_segmentation_options_t options = RAC_SEGMENTATION_OPTIONS_DEFAULT;

    rac_handle_t legacy = nullptr;
    check(rac_segmentation_create("fake-legacy-model", &legacy) == RAC_SUCCESS && legacy != nullptr,
          "legacy service creates");
    if (legacy) {
        check(rac_segmentation_initialize(legacy, "fake-legacy-model") == RAC_SUCCESS,
              "legacy service initializes");
        rac_segmentation_result_t legacy_result{};
        check(rac_segmentation_segment(legacy, &image, &options, &legacy_result) == RAC_SUCCESS,
              "legacy segment succeeds without the confidence extension");
        rac_segmentation_result_free(&legacy_result);

        rac_segmentation_result_t ignored_result{};
        auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
        check(rac_segmentation_segment_with_confidence(legacy, &image, &options, &ignored_result,
                                                       &confidence) == RAC_ERROR_NOT_SUPPORTED,
              "confidence is NOT_SUPPORTED on an engine without the extension");
        check(ignored_result.class_mask == nullptr && confidence.data == nullptr,
              "NOT_SUPPORTED leaves both outputs empty");

#if defined(RAC_HAVE_PROTOBUF)
        {
            rac_handle_t legacy_component = nullptr;
            check(rac_segmentation_component_create(&legacy_component) == RAC_SUCCESS &&
                      legacy_component != nullptr,
                  "legacy component creates");
            if (legacy_component) {
                check(rac_segmentation_component_load_model(legacy_component, "fake-legacy-model",
                                                            "fake-legacy-model",
                                                            "Fake Legacy") == RAC_SUCCESS,
                      "legacy component loads the fake model");
                runanywhere::v1::SegmentationResult proto_result;
                check(segment_proto(legacy_component, make_request(true, false), &proto_result) ==
                          RAC_ERROR_NOT_SUPPORTED,
                      "proto confidence request is NOT_SUPPORTED on the legacy engine");
                rac_segmentation_component_destroy(legacy_component);
            }
        }
#endif

        (void)rac_segmentation_cleanup(legacy);
        rac_segmentation_destroy(legacy);
    }
    check(rac_plugin_unregister("fake-segmentation-legacy") == RAC_SUCCESS,
          "legacy engine unregisters");

    // (2) The confidence-capable engine exercises the direct and proto paths.
    rac_engine_vtable_t confidence_vtable = make_vtable(kConfidenceManifest.manifest);
    check(rac_engine_manifest_attach_vtable(&kConfidenceManifest.manifest, &confidence_vtable) ==
              RAC_SUCCESS,
          "confidence manifest matches its vtable");
    check(rac_plugin_register(&confidence_vtable) == RAC_SUCCESS, "confidence engine registers");

    rac_handle_t handle = nullptr;
    check(rac_segmentation_create("fake-confidence-model", &handle) == RAC_SUCCESS &&
              handle != nullptr,
          "confidence service creates");
    if (handle) {
        check(rac_segmentation_initialize(handle, "fake-confidence-model") == RAC_SUCCESS,
              "confidence service initializes");
        run_entry_validation(handle, rgb);
        run_direct_cases(handle, rgb);
        (void)rac_segmentation_cleanup(handle);
        rac_segmentation_destroy(handle);
    }

#if defined(RAC_HAVE_PROTOBUF)
    {
        rac_handle_t component = nullptr;
        check(rac_segmentation_component_create(&component) == RAC_SUCCESS && component != nullptr,
              "confidence component creates");
        if (component) {
            runanywhere::v1::SegmentationResult before_load;
            check(segment_proto(component, make_request(false, false), &before_load) != RAC_SUCCESS,
                  "proto segmentation fails before a model is loaded");
            check(rac_segmentation_component_load_model(component, "fake-confidence-model",
                                                        "fake-confidence-model",
                                                        "Fake Confidence") == RAC_SUCCESS,
                  "confidence component loads the fake model");
            run_proto_cases(component);
            rac_segmentation_component_destroy(component);
        }
    }
#endif

    check(rac_plugin_unregister("fake-segmentation-confidence") == RAC_SUCCESS,
          "confidence engine unregisters");

    std::fprintf(stdout, "\n%d failures\n", g_failures);
    return g_failures == 0 ? 0 : 1;
}
