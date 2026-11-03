/**
 * @file test_segmentation_onnx.cpp
 * @brief Real-ORT SegFormer contract, proto ABI, and lifecycle-drain tests.
 */

#include "model_types.pb.h"
#include "segmentation.pb.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <future>
#include <mutex>
#include <string>
#include <vector>

#include "features/segmentation/segmentation_internal.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/segmentation/rac_segmentation.h"
#include "rac/features/segmentation/rac_segmentation_confidence.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#ifndef RAC_SEGMENTATION_FIXTURE_DIR
#error "RAC_SEGMENTATION_FIXTURE_DIR must name the real ONNX fixture bundle"
#endif

extern "C" const rac_segmentation_service_ops_t g_onnx_segmentation_ops;
extern "C" const rac_segmentation_confidence_ops_v1_t g_onnx_segmentation_confidence_ops;

namespace {

using namespace std::chrono_literals;

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

const rac_segmentation_service_ops_t* fixture_segmentation_ops();

constexpr const char* kFixtureName = "onnx-segmentation-fixture";
constexpr const char* kFixtureDisplayName = "ONNX Segmentation Fixture";
constexpr const char* kFixtureVersion = "1";
constexpr int32_t kFixturePriority = 1000;
const uint32_t kFixtureFormats[] = {static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ONNX)};
const rac_primitive_t kFixturePrimitives[] = {RAC_PRIMITIVE_SEGMENT};

rac_engine_vtable_t make_fixture_vtable() {
    rac_engine_vtable_t vtable{};
    vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vtable.metadata.name = kFixtureName;
    vtable.metadata.display_name = kFixtureDisplayName;
    vtable.metadata.engine_version = kFixtureVersion;
    vtable.metadata.priority = kFixturePriority;
    vtable.metadata.capability_flags = RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1;
    vtable.metadata.formats = kFixtureFormats;
    vtable.metadata.formats_count = 1;
    vtable.segmentation_ops = fixture_segmentation_ops();
    return vtable;
}

std::vector<uint8_t> make_rgb(uint32_t width, uint32_t height) {
    std::vector<uint8_t> rgb(static_cast<size_t>(width) * height * 3);
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const size_t offset = (static_cast<size_t>(y) * width + x) * 3;
            rgb[offset] = static_cast<uint8_t>((x * 7U + y * 3U) % 256U);
            rgb[offset + 1] = static_cast<uint8_t>((x * 11U + y * 5U + 17U) % 256U);
            rgb[offset + 2] = static_cast<uint8_t>((x * 13U + y * 19U + 29U) % 256U);
        }
    }
    return rgb;
}

std::vector<uint8_t> encode_pixels(const std::vector<uint8_t>& rgb,
                                   runanywhere::v1::SegmentationPixelFormat format) {
    if (format == runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8) {
        return rgb;
    }
    std::vector<uint8_t> packed((rgb.size() / 3) * 4);
    for (size_t pixel = 0; pixel < rgb.size() / 3; ++pixel) {
        const uint8_t red = rgb[pixel * 3];
        const uint8_t green = rgb[pixel * 3 + 1];
        const uint8_t blue = rgb[pixel * 3 + 2];
        if (format == runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_BGRA8) {
            packed[pixel * 4] = blue;
            packed[pixel * 4 + 1] = green;
            packed[pixel * 4 + 2] = red;
        } else {
            packed[pixel * 4] = red;
            packed[pixel * 4 + 1] = green;
            packed[pixel * 4 + 2] = blue;
        }
        packed[pixel * 4 + 3] = static_cast<uint8_t>(pixel * 17U);
    }
    return packed;
}

runanywhere::v1::SegmentationRequest make_request(uint32_t width, uint32_t height,
                                                  const std::vector<uint8_t>& rgb,
                                                  runanywhere::v1::SegmentationPixelFormat format,
                                                  bool diagnostic) {
    runanywhere::v1::SegmentationRequest request;
    auto* image = request.mutable_image();
    const auto packed = encode_pixels(rgb, format);
    image->set_data(packed.data(), packed.size());
    image->set_width(width);
    image->set_height(height);
    image->set_pixel_format(format);
    request.mutable_options()->set_include_diagnostic_rgba(diagnostic);
    return request;
}

bool segment_proto(rac_handle_t component, const runanywhere::v1::SegmentationRequest& request,
                   runanywhere::v1::SegmentationResult* out, rac_result_t* out_rc = nullptr) {
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        return false;
    }
    rac_proto_buffer_t result{};
    const rac_result_t rc = rac_segmentation_component_segment_proto(
        component, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result);
    if (out_rc) {
        *out_rc = rc;
    }
    const bool parsed =
        rc == RAC_SUCCESS && out && out->ParseFromArray(result.data, static_cast<int>(result.size));
    rac_proto_buffer_free(&result);
    return parsed;
}

bool segment_lifecycle_proto(const runanywhere::v1::SegmentationRequest& request,
                             runanywhere::v1::SegmentationResult* out,
                             rac_result_t* out_rc = nullptr) {
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        return false;
    }
    rac_proto_buffer_t result{};
    const rac_result_t rc = rac_segmentation_segment_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result);
    if (out_rc) {
        *out_rc = rc;
    }
    const bool parsed =
        rc == RAC_SUCCESS && out && out->ParseFromArray(result.data, static_cast<int>(result.size));
    rac_proto_buffer_free(&result);
    return parsed;
}

bool unload_lifecycle_model(const std::string& model_id, runanywhere::v1::ModelUnloadResult* out,
                            rac_result_t* out_rc = nullptr) {
    runanywhere::v1::ModelUnloadRequest request;
    request.set_model_id(model_id);
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        return false;
    }
    rac_proto_buffer_t result{};
    const rac_result_t rc = rac_model_lifecycle_unload_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result);
    if (out_rc) {
        *out_rc = rc;
    }
    const bool parsed =
        rc == RAC_SUCCESS && out && out->ParseFromArray(result.data, static_cast<int>(result.size));
    rac_proto_buffer_free(&result);
    return parsed;
}

bool valid_fixture_result(const runanywhere::v1::SegmentationResult& result, uint32_t width,
                          uint32_t height, const char* expected_model_id = "fixture-segformer") {
    const size_t pixels = static_cast<size_t>(width) * height;
    if (result.width() != width || result.height() != height ||
        result.class_mask_u16_le().size() != pixels * sizeof(uint16_t) ||
        result.diagnostic_rgba().size() != pixels * 4 || result.class_summaries_size() != 1 ||
        result.model_id() != expected_model_id) {
        return false;
    }
    for (size_t pixel = 0; pixel < pixels; ++pixel) {
        if (static_cast<uint8_t>(result.class_mask_u16_le()[pixel * 2]) != 149U ||
            static_cast<uint8_t>(result.class_mask_u16_le()[pixel * 2 + 1]) != 0U ||
            static_cast<uint8_t>(result.diagnostic_rgba()[pixel * 4 + 3]) != 255U) {
            return false;
        }
    }
    // Coverage share is commons-owned on the wire (SegmentationClassSummary.fraction).
    const auto& summary = result.class_summaries(0);
    return summary.class_id() == 149 && summary.pixel_count() == pixels &&
           summary.fraction() == 1.0f && summary.label() == "class_149";
}

struct OperationGate {
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false;
    bool release = false;
};

std::atomic<OperationGate*> g_provider_operation_gate{nullptr};

void block_admitted_operation(rac_handle_t, void* user_data) {
    auto* gate = static_cast<OperationGate*>(user_data);
    std::unique_lock<std::mutex> lock(gate->mutex);
    gate->entered = true;
    gate->cv.notify_all();
    gate->cv.wait(lock, [&] { return gate->release; });
}

bool wait_for_gate(OperationGate* gate) {
    std::unique_lock<std::mutex> lock(gate->mutex);
    return gate->cv.wait_for(lock, 2s, [&] { return gate->entered; });
}

void release_gate(OperationGate* gate) {
    {
        std::lock_guard<std::mutex> lock(gate->mutex);
        gate->release = true;
    }
    gate->cv.notify_all();
}

rac_result_t fixture_segment(void* impl, const rac_segmentation_image_t* image,
                             const rac_segmentation_options_t* options,
                             rac_segmentation_result_t* out_result) {
    if (auto* gate = g_provider_operation_gate.load(std::memory_order_acquire)) {
        block_admitted_operation(nullptr, gate);
    }
    return g_onnx_segmentation_ops.segment(impl, image, options, out_result);
}

const rac_segmentation_service_ops_t* fixture_segmentation_ops() {
    static const rac_segmentation_service_ops_t kOps = {
        g_onnx_segmentation_ops.initialize, fixture_segment, g_onnx_segmentation_ops.cleanup,
        g_onnx_segmentation_ops.destroy, g_onnx_segmentation_ops.create};
    return &kOps;
}

rac_result_t fixture_segment_with_confidence(
    void* impl, const rac_segmentation_image_t* image, const rac_segmentation_options_t* options,
    rac_segmentation_result_t* out_result, rac_segmentation_confidence_mask_v1_t* out_confidence) {
    return g_onnx_segmentation_confidence_ops.segment(impl, image, options, out_result,
                                                      out_confidence);
}

const rac_segmentation_confidence_ops_v1_t kFixtureConfidenceOps = {
    sizeof(rac_segmentation_confidence_ops_v1_t), RAC_SEGMENTATION_CONFIDENCE_VERSION_1,
    fixture_segment_with_confidence};

// The legacy manifest prefix must match make_fixture_vtable() field for field:
// rac_engine_manifest_validate_vtable rejects any disagreement.
const rac_segmentation_confidence_manifest_v1_t kFixtureConfidenceManifest = {
    .manifest =
        {
            .name = kFixtureName,
            .display_name = kFixtureDisplayName,
            .version = kFixtureVersion,
            .package_owner = "runanywhere-tests",
            .package_name = "rac_segmentation_onnx_test",
            .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
            .priority = kFixturePriority,
            .capability_flags = RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1,
            .primitives = kFixturePrimitives,
            .primitives_count = sizeof(kFixturePrimitives) / sizeof(kFixturePrimitives[0]),
            .runtimes = nullptr,
            .runtimes_count = 0,
            .formats = kFixtureFormats,
            .formats_count = sizeof(kFixtureFormats) / sizeof(kFixtureFormats[0]),
            .reserved_0 = 0,
            .reserved_1 = 0,
        },
    .struct_size = sizeof(rac_segmentation_confidence_manifest_v1_t),
    .version = RAC_SEGMENTATION_CONFIDENCE_VERSION_1,
    .confidence_ops = &kFixtureConfidenceOps,
};

}  // namespace

int main() {
    std::fprintf(stdout, "test_segmentation_onnx (real tiny ONNX graph)\n");
    const rac_engine_vtable_t vtable = make_fixture_vtable();
    CHECK(rac_engine_manifest_attach_vtable(&kFixtureConfidenceManifest.manifest, &vtable) ==
              RAC_SUCCESS,
          "fixture confidence manifest matches the fixture vtable");
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "fixture segmentation plugin registers");

    rac_handle_t component = nullptr;
    CHECK(rac_segmentation_component_create(&component) == RAC_SUCCESS && component != nullptr,
          "segmentation component creates");
    CHECK(rac_segmentation_component_load_model(component, RAC_SEGMENTATION_FIXTURE_DIR,
                                                "fixture-segformer",
                                                "Fixture SegFormer") == RAC_SUCCESS,
          "real tiny ONNX fixture loads through Commons lifecycle without a license gate");
    CHECK(rac_segmentation_component_is_loaded(component) == RAC_TRUE,
          "component reports loaded state");

    constexpr uint32_t kWidth = 7;
    constexpr uint32_t kHeight = 5;
    const auto rgb = make_rgb(kWidth, kHeight);
    std::vector<uint8_t> canonical_mask;
    std::vector<uint8_t> canonical_diagnostic;
    for (const auto format : {runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8,
                              runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGBA8,
                              runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_BGRA8}) {
        runanywhere::v1::SegmentationResult result;
        CHECK(segment_proto(component, make_request(kWidth, kHeight, rgb, format, true), &result),
              "packed pixel format segments through proto ABI");
        CHECK(valid_fixture_result(result, kWidth, kHeight),
              "source-sized u16 mask, RGBA diagnostic, summary, and model ID are canonical");
        std::vector<uint8_t> mask(result.class_mask_u16_le().begin(),
                                  result.class_mask_u16_le().end());
        std::vector<uint8_t> diagnostic(result.diagnostic_rgba().begin(),
                                        result.diagnostic_rgba().end());
        if (canonical_mask.empty()) {
            canonical_mask = std::move(mask);
            canonical_diagnostic = std::move(diagnostic);
        } else {
            CHECK(mask == canonical_mask && diagnostic == canonical_diagnostic,
                  "RGB8, RGBA8, and BGRA8 produce identical stable outputs");
        }
    }

    // Confidence contract. The fixture's class bias is arange(150), so the
    // winning class (149) always has softmax probability
    // 1 / sum_{j=0..149} e^-j = 0.6321205588..., and the documented 8-bit
    // quantization yields exactly 161 for every source pixel. The same image is
    // driven through the direct and proto entry points and the buffers must be
    // byte-identical.
    const size_t kPixels = static_cast<size_t>(kWidth) * kHeight;
    std::vector<uint8_t> direct_class_mask;
    std::vector<uint8_t> direct_diagnostic;
    std::vector<uint8_t> direct_confidence;
    {
        rac_handle_t direct = nullptr;
        CHECK(rac_segmentation_create(RAC_SEGMENTATION_FIXTURE_DIR, &direct) == RAC_SUCCESS &&
                  direct != nullptr,
              "direct segmentation service creates against the fixture");
        if (direct) {
            CHECK(rac_segmentation_initialize(direct, RAC_SEGMENTATION_FIXTURE_DIR) == RAC_SUCCESS,
                  "direct segmentation service initializes the fixture");
            rac_segmentation_image_t image{};
            image.data = rgb.data();
            image.data_size = rgb.size();
            image.width = kWidth;
            image.height = kHeight;
            image.stride_bytes = static_cast<size_t>(kWidth) * 3;
            image.pixel_format = RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
            rac_segmentation_options_t options = RAC_SEGMENTATION_OPTIONS_DEFAULT;
            options.include_diagnostic_rgba = RAC_TRUE;
            rac_segmentation_result_t result{};
            auto confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
            const rac_result_t rc = rac_segmentation_segment_with_confidence(
                direct, &image, &options, &result, &confidence);
            CHECK(rc == RAC_SUCCESS, "direct path returns a confidence mask");
            CHECK(confidence.size == kPixels && confidence.data != nullptr,
                  "direct confidence mask is exactly width * height bytes");
            bool all_161 = confidence.data != nullptr;
            for (size_t i = 0; i < confidence.size && all_161; ++i) {
                all_161 = confidence.data[i] == 161U;
            }
            CHECK(all_161, "direct confidence is the quantized winning-class probability (161)");
            if (result.class_mask && result.class_mask_count == kPixels) {
                direct_class_mask.resize(kPixels * sizeof(uint16_t));
                for (size_t i = 0; i < kPixels; ++i) {
                    const uint16_t value = result.class_mask[i];
                    direct_class_mask[i * 2] = static_cast<uint8_t>(value & 0xffU);
                    direct_class_mask[i * 2 + 1] = static_cast<uint8_t>((value >> 8U) & 0xffU);
                }
            }
            if (result.diagnostic_rgba && result.diagnostic_rgba_size > 0) {
                direct_diagnostic.assign(result.diagnostic_rgba,
                                         result.diagnostic_rgba + result.diagnostic_rgba_size);
            }
            if (confidence.data && confidence.size > 0) {
                direct_confidence.assign(confidence.data, confidence.data + confidence.size);
            }
            rac_segmentation_result_free(&result);
            rac_segmentation_confidence_mask_free(&confidence);
            (void)rac_segmentation_cleanup(direct);
            rac_segmentation_destroy(direct);
        }
    }

    {
        auto request = make_request(kWidth, kHeight, rgb,
                                    runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8, true);
        request.mutable_options()->set_include_confidence(true);
        runanywhere::v1::SegmentationResult result;
        CHECK(segment_proto(component, request, &result), "proto path returns a confidence mask");
        CHECK(result.confidence_mask_u8().size() == kPixels,
              "proto confidence mask is exactly width * height bytes");
        bool all_161 = result.confidence_mask_u8().size() == kPixels;
        for (size_t i = 0; i < result.confidence_mask_u8().size() && all_161; ++i) {
            all_161 = static_cast<uint8_t>(result.confidence_mask_u8()[i]) == 161U;
        }
        CHECK(all_161, "proto confidence matches the quantized softmax value (161)");
        CHECK(std::vector<uint8_t>(result.confidence_mask_u8().begin(),
                                   result.confidence_mask_u8().end()) == direct_confidence,
              "direct and proto paths return byte-identical confidence masks");
        CHECK(std::vector<uint8_t>(result.class_mask_u16_le().begin(),
                                   result.class_mask_u16_le().end()) == direct_class_mask,
              "direct and proto paths return byte-identical class masks");
        CHECK(std::vector<uint8_t>(result.diagnostic_rgba().begin(),
                                   result.diagnostic_rgba().end()) == direct_diagnostic,
              "direct and proto paths return byte-identical diagnostics");
    }

    {
        auto request = make_request(kWidth, kHeight, rgb,
                                    runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8, false);
        runanywhere::v1::SegmentationResult result;
        CHECK(segment_proto(component, request, &result) && result.confidence_mask_u8().empty(),
              "proto path omits confidence when it was not requested");
    }

    auto oversized = make_request(4097, 1, make_rgb(4097, 1),
                                  runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8, false);
    runanywhere::v1::SegmentationResult ignored;
    rac_result_t oversized_rc = RAC_SUCCESS;
    CHECK(!segment_proto(component, oversized, &ignored, &oversized_rc) &&
              oversized_rc == RAC_ERROR_INVALID_PARAMETER,
          "each source dimension is capped before preprocessing allocation");

    auto malformed =
        make_request(kWidth, kHeight, rgb, runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8, false);
    malformed.mutable_image()->mutable_data()->pop_back();
    rac_result_t malformed_rc = RAC_SUCCESS;
    CHECK(!segment_proto(component, malformed, &ignored, &malformed_rc) &&
              malformed_rc == RAC_ERROR_INVALID_ARGUMENT,
          "proto ABI rejects non-tightly-packed pixel bytes");

    OperationGate gate;
    rac::segmentation::set_component_operation_admitted_test_hook(block_admitted_operation, &gate);
    auto getter = std::async(std::launch::async,
                             [&] { return rac_segmentation_component_is_loaded(component); });
    CHECK(wait_for_gate(&gate), "component getter pauses after lifetime admission");
    rac::segmentation::set_component_operation_admitted_test_hook(nullptr, nullptr);
    auto destroy =
        std::async(std::launch::async, [&] { rac_segmentation_component_destroy(component); });
    CHECK(destroy.wait_for(50ms) == std::future_status::timeout,
          "component destroy drains an admitted operation lease");
    release_gate(&gate);
    CHECK(getter.wait_for(2s) == std::future_status::ready && getter.get() == RAC_TRUE,
          "admitted operation finishes before component teardown");
    CHECK(destroy.wait_for(2s) == std::future_status::ready,
          "component destroy completes after lease drain");
    destroy.get();

    // Exercise the exact handle-free lifecycle ABI used by Swift, Kotlin, and
    // Web. The fixture ops only add a deterministic admission gate; inference
    // still delegates to the real ONNX provider and real ORT session.
    rac_model_lifecycle_reset();
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "canonical lifecycle registry creates");
    if (registry) {
        runanywhere::v1::ModelInfo model;
        model.set_id("fixture-segformer-lifecycle");
        model.set_name("Fixture SegFormer lifecycle");
        model.set_category(runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION);
        model.set_format(runanywhere::v1::MODEL_FORMAT_ONNX);
        model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
        model.set_local_path(RAC_SEGMENTATION_FIXTURE_DIR);
        model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
        model.set_is_available(true);
        std::string model_bytes;
        CHECK(model.SerializeToString(&model_bytes) &&
                  rac_model_registry_register_proto(
                      registry, reinterpret_cast<const uint8_t*>(model_bytes.data()),
                      model_bytes.size()) == RAC_SUCCESS,
              "real segmentation fixture registers in the canonical model registry");

        runanywhere::v1::ModelLoadRequest load_request;
        load_request.set_model_id(model.id());
        std::string load_bytes;
        (void)load_request.SerializeToString(&load_bytes);
        rac_proto_buffer_t lifecycle_output{};
        const rac_result_t load_rc = rac_model_lifecycle_load_proto(
            registry, reinterpret_cast<const uint8_t*>(load_bytes.data()), load_bytes.size(),
            &lifecycle_output);
        runanywhere::v1::ModelLoadResult load_result;
        const bool lifecycle_loaded =
            load_rc == RAC_SUCCESS &&
            load_result.ParseFromArray(lifecycle_output.data,
                                       static_cast<int>(lifecycle_output.size)) &&
            !load_result.has_error() && load_result.model_id() == model.id();
        CHECK(lifecycle_loaded,
              "canonical model lifecycle loads the real ONNX segmentation fixture");
        rac_proto_buffer_free(&lifecycle_output);

        const auto lifecycle_request = make_request(
            kWidth, kHeight, rgb, runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8, true);
        runanywhere::v1::SegmentationResult lifecycle_result;
        CHECK(lifecycle_loaded && segment_lifecycle_proto(lifecycle_request, &lifecycle_result),
              "handle-free lifecycle segmentation dispatches through real ORT");
        CHECK(lifecycle_loaded &&
                  valid_fixture_result(lifecycle_result, kWidth, kHeight, model.id().c_str()),
              "handle-free result preserves canonical model ID and source-sized mask");

        if (lifecycle_loaded) {
            OperationGate lifecycle_gate;
            g_provider_operation_gate.store(&lifecycle_gate, std::memory_order_release);
            runanywhere::v1::SegmentationResult in_flight_result;
            rac_result_t in_flight_rc = RAC_SUCCESS;
            auto in_flight = std::async(std::launch::async, [&] {
                return segment_lifecycle_proto(lifecycle_request, &in_flight_result, &in_flight_rc);
            });
            CHECK(wait_for_gate(&lifecycle_gate),
                  "handle-free inference pauses after global lifecycle admission");
            g_provider_operation_gate.store(nullptr, std::memory_order_release);

            runanywhere::v1::ModelUnloadResult unload_result;
            rac_result_t unload_rc = RAC_SUCCESS;
            auto unload = std::async(std::launch::async, [&] {
                return unload_lifecycle_model(model.id(), &unload_result, &unload_rc);
            });
            CHECK(unload.wait_for(50ms) == std::future_status::timeout,
                  "global lifecycle unload drains an admitted handle-free inference lease");
            release_gate(&lifecycle_gate);
            CHECK(in_flight.wait_for(2s) == std::future_status::ready && in_flight.get() &&
                      in_flight_rc == RAC_SUCCESS &&
                      valid_fixture_result(in_flight_result, kWidth, kHeight, model.id().c_str()),
                  "admitted handle-free inference completes with the canonical model");
            CHECK(unload.wait_for(2s) == std::future_status::ready && unload.get() &&
                      unload_rc == RAC_SUCCESS && !unload_result.has_error() &&
                      unload_result.unloaded_model_ids_size() == 1 &&
                      unload_result.unloaded_model_ids(0) == model.id(),
                  "canonical lifecycle unload completes after the global lease drains");

            runanywhere::v1::SegmentationResult after_unload;
            rac_result_t after_unload_rc = RAC_SUCCESS;
            CHECK(!segment_lifecycle_proto(lifecycle_request, &after_unload, &after_unload_rc) &&
                      after_unload_rc == RAC_ERROR_NOT_INITIALIZED,
                  "handle-free segmentation rejects dispatch after canonical unload");
        }

        rac_model_registry_destroy(registry);
    }
    rac_model_lifecycle_reset();

    CHECK(rac_plugin_unregister("onnx-segmentation-fixture") == RAC_SUCCESS,
          "fixture plugin unregisters");
    std::fprintf(stdout, "\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
