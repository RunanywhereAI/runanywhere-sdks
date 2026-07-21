/**
 * @file test_segmentation_onnx_exact.cpp
 * @brief Opt-in parity gate for the pinned NVIDIA SegFormer ONNX bundle.
 */

#include "segmentation.pb.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/features/segmentation/rac_segmentation.h"
#include "rac/foundation/rac_sha256.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"

namespace {

constexpr const char* kLicenseEnv = "RAC_ACCEPT_NVIDIA_SEGFORMER_NONCOMMERCIAL_LICENSE";
constexpr const char* kExpectedMaskSha256 =
    "fd68d059416df80f316c61292dd32e3ea5d7e90b17e568c8eb40f0cf0db317e7";

bool accepted_license() {
    const char* value = std::getenv(kLicenseEnv);
    return value && (std::strcmp(value, "1") == 0 || std::strcmp(value, "true") == 0 ||
                     std::strcmp(value, "TRUE") == 0 || std::strcmp(value, "yes") == 0 ||
                     std::strcmp(value, "YES") == 0);
}

std::vector<uint8_t> make_oracle_rgb() {
    constexpr uint32_t kWidth = 37;
    constexpr uint32_t kHeight = 29;
    std::vector<uint8_t> rgb(static_cast<size_t>(kWidth) * kHeight * 3);
    for (uint32_t y = 0; y < kHeight; ++y) {
        for (uint32_t x = 0; x < kWidth; ++x) {
            const size_t offset = (static_cast<size_t>(y) * kWidth + x) * 3;
            rgb[offset] = static_cast<uint8_t>((x * 7U + y * 3U) % 256U);
            rgb[offset + 1] = static_cast<uint8_t>((x * 11U + y * 5U + 17U) % 256U);
            rgb[offset + 2] = static_cast<uint8_t>((x * 13U + y * 19U + 29U) % 256U);
        }
    }
    return rgb;
}

}  // namespace

int main() {
    const char* model_dir = std::getenv("RAC_SEGFORMER_MODEL_DIR");
    if (!model_dir || model_dir[0] == '\0') {
        std::fprintf(stdout,
                     "SKIP: set RAC_SEGFORMER_MODEL_DIR to the pinned Optimum ONNX bundle\n");
        return 77;
    }
    if (!accepted_license()) {
        std::fprintf(stdout, "SKIP: exact NVIDIA model requires explicit %s=1 license acceptance\n",
                     kLicenseEnv);
        return 77;
    }

    const rac_engine_vtable_t* vtable = rac_plugin_entry_onnx();
    if (!vtable || rac_plugin_register(vtable) != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: production ONNX plugin registration\n");
        return 1;
    }

    rac_handle_t component = nullptr;
    if (rac_segmentation_component_create(&component) != RAC_SUCCESS || !component) {
        std::fprintf(stderr, "FAIL: segmentation component creation\n");
        (void)rac_plugin_unregister("onnx");
        return 1;
    }
    const rac_result_t load_rc = rac_segmentation_component_load_model(
        component, model_dir, "nvidia-segformer-b0-ade-512-512", "NVIDIA SegFormer B0 ADE20K");
    if (load_rc != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: exact bundle load returned %d\n", load_rc);
        rac_segmentation_component_destroy(component);
        (void)rac_plugin_unregister("onnx");
        return 1;
    }

    constexpr uint32_t kWidth = 37;
    constexpr uint32_t kHeight = 29;
    const auto rgb = make_oracle_rgb();
    runanywhere::v1::SegmentationRequest request;
    request.mutable_image()->set_data(rgb.data(), rgb.size());
    request.mutable_image()->set_width(kWidth);
    request.mutable_image()->set_height(kHeight);
    request.mutable_image()->set_pixel_format(runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8);
    request.mutable_options()->set_include_diagnostic_rgba(true);
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        std::fprintf(stderr, "FAIL: exact SegFormer request serialization\n");
        rac_segmentation_component_destroy(component);
        (void)rac_plugin_unregister("onnx");
        return 1;
    }

    rac_proto_buffer_t response_bytes{};
    const rac_result_t segment_rc = rac_segmentation_component_segment_proto(
        component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
        &response_bytes);
    runanywhere::v1::SegmentationResult result;
    const bool parsed =
        segment_rc == RAC_SUCCESS &&
        result.ParseFromArray(response_bytes.data, static_cast<int>(response_bytes.size));
    rac_proto_buffer_free(&response_bytes);

    bool valid = parsed && result.width() == kWidth && result.height() == kHeight &&
                 result.class_mask_u16_le().size() == kWidth * kHeight * sizeof(uint16_t) &&
                 result.diagnostic_rgba().size() == kWidth * kHeight * 4 &&
                 result.model_id() == "nvidia-segformer-b0-ade-512-512" &&
                 runanywhere::sha256_hex(result.class_mask_u16_le()) == kExpectedMaskSha256;

    std::array<uint64_t, 150> counts{};
    if (parsed) {
        for (size_t pixel = 0; pixel < static_cast<size_t>(kWidth) * kHeight; ++pixel) {
            const auto low = static_cast<uint8_t>(result.class_mask_u16_le()[pixel * 2]);
            const auto high = static_cast<uint8_t>(result.class_mask_u16_le()[pixel * 2 + 1]);
            const uint16_t class_id = static_cast<uint16_t>(low | (high << 8U));
            if (class_id >= counts.size()) {
                valid = false;
                break;
            }
            ++counts[class_id];
        }
    }
    valid = valid && counts[0] == 320 && counts[2] == 699 && counts[5] == 24 && counts[29] == 29 &&
            counts[59] == 1;
    uint64_t unexpected = 0;
    for (size_t class_id = 0; class_id < counts.size(); ++class_id) {
        if (class_id != 0 && class_id != 2 && class_id != 5 && class_id != 29 && class_id != 59) {
            unexpected += counts[class_id];
        }
    }
    valid = valid && unexpected == 0;

    (void)rac_segmentation_component_unload(component);
    rac_segmentation_component_destroy(component);
    (void)rac_plugin_unregister("onnx");

    if (!valid) {
        std::fprintf(stderr, "FAIL: exact SegFormer mask parity (rc=%d, parsed=%d, sha=%s)\n",
                     segment_rc, parsed ? 1 : 0,
                     parsed ? runanywhere::sha256_hex(result.class_mask_u16_le()).c_str() : "-");
        return 1;
    }
    std::fprintf(stdout,
                 "PASS: pinned bc01a2c SegFormer mask SHA/counts match independent ORT oracle\n");
    return 0;
}
