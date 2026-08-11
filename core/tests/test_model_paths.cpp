/**
 * @file test_model_paths.cpp
 * @brief Regression tests for canonical model path construction.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

#define EXPECT_TRUE(_cond)                                                          \
    do {                                                                            \
        if (!(_cond)) {                                                             \
            std::fprintf(stderr, "FAIL @ %s:%d: %s\n", __FILE__, __LINE__, #_cond); \
            return 1;                                                               \
        }                                                                           \
    } while (0)

#define EXPECT_RC(_rc_expr, _expected)                                                         \
    do {                                                                                       \
        rac_result_t _rc = (_rc_expr);                                                         \
        if (_rc != (_expected)) {                                                              \
            std::fprintf(stderr, "FAIL @ %s:%d: rc=%d expected=%d\n", __FILE__, __LINE__, _rc, \
                         (_expected));                                                         \
            return 1;                                                                          \
        }                                                                                      \
    } while (0)

int test_mlx_framework_directory_uses_mlx_segment() {
    constexpr const char* kBase = "/tmp/runanywhere-model-path-test";
    constexpr const char* kModelId = "mlx-qwen3-0.6b-4bit";

    EXPECT_RC(rac_model_paths_set_base_dir(kBase), RAC_SUCCESS);

    char framework_path[512] = {};
    EXPECT_RC(rac_model_paths_get_framework_directory(RAC_FRAMEWORK_MLX, framework_path,
                                                      sizeof(framework_path)),
              RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(framework_path,
                            "/tmp/runanywhere-model-path-test/RunAnywhere/Models/MLX") == 0);

    char model_path[512] = {};
    EXPECT_RC(
        rac_model_paths_get_model_folder(kModelId, RAC_FRAMEWORK_MLX, model_path,
                                         sizeof(model_path)),
        RAC_SUCCESS);
    EXPECT_TRUE(
        std::strcmp(model_path,
                    "/tmp/runanywhere-model-path-test/RunAnywhere/Models/MLX/"
                    "mlx-qwen3-0.6b-4bit") == 0);

    char expected_path[512] = {};
    EXPECT_RC(rac_model_paths_get_expected_model_path(
                  kModelId, RAC_FRAMEWORK_MLX, RAC_MODEL_FORMAT_SAFETENSORS, expected_path,
                  sizeof(expected_path)),
              RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(expected_path, model_path) == 0);

    char extracted_id[256] = {};
    EXPECT_RC(rac_model_paths_extract_model_id(model_path, extracted_id, sizeof(extracted_id)),
              RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(extracted_id, kModelId) == 0);

    rac_inference_framework_t extracted_framework = RAC_FRAMEWORK_UNKNOWN;
    EXPECT_RC(rac_model_paths_extract_framework(model_path, &extracted_framework), RAC_SUCCESS);
    EXPECT_TRUE(extracted_framework == RAC_FRAMEWORK_MLX);
    return 0;
}

}  // namespace

int main() {
    if (test_mlx_framework_directory_uses_mlx_segment() != 0) {
        return 1;
    }
    std::printf("model path tests passed\n");
    return 0;
}
