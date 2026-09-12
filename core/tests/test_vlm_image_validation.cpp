/**
 * @file test_vlm_image_validation.cpp
 * @brief Regression coverage for direct C-struct VLM raw-image validation.
 */

#include <cstdint>
#include <cstdio>
#include <limits>

#include "rac/features/vlm/rac_vlm_service.h"

namespace {

#define EXPECT_TRUE(_cond)                                                          \
    do {                                                                            \
        if (!(_cond)) {                                                             \
            std::fprintf(stderr, "FAIL @ %s:%d: %s\n", __FILE__, __LINE__, #_cond); \
            return 1;                                                               \
        }                                                                           \
    } while (0)

struct DispatchCounts {
    int process = 0;
    int process_stream = 0;
};

rac_result_t fake_process(void* impl, const rac_vlm_image_t*, const char*,
                          const rac_vlm_options_t*, rac_vlm_result_t*) {
    ++static_cast<DispatchCounts*>(impl)->process;
    return RAC_SUCCESS;
}

rac_result_t fake_process_stream(void* impl, const rac_vlm_image_t*, const char*,
                                 const rac_vlm_options_t*, rac_vlm_stream_callback_fn, void*) {
    ++static_cast<DispatchCounts*>(impl)->process_stream;
    return RAC_SUCCESS;
}

rac_bool_t keep_streaming(const char*, void*) {
    return RAC_TRUE;
}

int test_direct_rgb_image_validation() {
    DispatchCounts dispatch_counts;
    rac_vlm_service_ops_t ops{};
    ops.process = fake_process;
    ops.process_stream = fake_process_stream;
    rac_vlm_service_t service{&ops, &dispatch_counts, "test-vlm"};

    uint8_t pixels[12]{};
    rac_vlm_image_t image{};
    image.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
    image.pixel_data = pixels;
    image.width = 2;
    image.height = 2;
    image.data_size = sizeof(pixels) - 1;

    rac_vlm_result_t result{};
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) ==
                RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(rac_vlm_process_stream(&service, &image, "describe", nullptr, keep_streaming,
                                       nullptr) == RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(dispatch_counts.process == 0);
    EXPECT_TRUE(dispatch_counts.process_stream == 0);

    image.data_size = sizeof(pixels);
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) == RAC_SUCCESS);
    EXPECT_TRUE(rac_vlm_process_stream(&service, &image, "describe", nullptr, keep_streaming,
                                       nullptr) == RAC_SUCCESS);
    EXPECT_TRUE(dispatch_counts.process == 1);
    EXPECT_TRUE(dispatch_counts.process_stream == 1);

    image.width = 0;
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) ==
                RAC_ERROR_INVALID_ARGUMENT);

    image.width = 2;
    image.height = 0;
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) ==
                RAC_ERROR_INVALID_ARGUMENT);

    image.height = 2;
    image.pixel_data = nullptr;
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) ==
                RAC_ERROR_INVALID_ARGUMENT);

    image.pixel_data = pixels;
    image.width = std::numeric_limits<uint32_t>::max();
    image.height = std::numeric_limits<uint32_t>::max();
    image.data_size = std::numeric_limits<size_t>::max();
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) ==
                RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(dispatch_counts.process == 1);

    image = {};
    image.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
    image.file_path = "/tmp/image.png";
    EXPECT_TRUE(rac_vlm_process(&service, &image, "describe", nullptr, &result) == RAC_SUCCESS);
    EXPECT_TRUE(dispatch_counts.process == 2);
    return 0;
}

}  // namespace

int main() {
    if (test_direct_rgb_image_validation() != 0) {
        return 1;
    }
    std::printf("vlm image validation tests passed\n");
    return 0;
}
