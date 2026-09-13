/**
 * @file test_model_paths.cpp
 * @brief Regression tests for canonical model path construction.
 */

#include <cstdio>
#include <cstring>

#include "infrastructure/rac_path_safety_internal.h"
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

/**
 * @brief Tests shared path separator search and filename extraction across platforms.
 *
 * @return 0 on success, non-zero on test assertion failure.
 */
int test_shared_path_separator_helpers() {
    using namespace rac::path;

    // 1. Null safety
    EXPECT_TRUE(find_last_path_separator(static_cast<const char*>(nullptr)) == nullptr);
    EXPECT_TRUE(find_last_path_separator(static_cast<char*>(nullptr)) == nullptr);
    EXPECT_TRUE(filename_from_path(nullptr) == nullptr);

    // 2. String without separators
    EXPECT_TRUE(find_last_path_separator("pure_model_id") == nullptr);
    EXPECT_TRUE(std::strcmp(filename_from_path("pure_model_id"), "pure_model_id") == 0);

    // 3. POSIX forward slash paths
    const char* posix_path = "/var/models/stt/whisper.bin";
    const char* posix_sep = find_last_path_separator(posix_path);
    EXPECT_TRUE(posix_sep != nullptr && std::strcmp(posix_sep, "/whisper.bin") == 0);
    EXPECT_TRUE(std::strcmp(filename_from_path(posix_path), "whisper.bin") == 0);

    // 4. Windows backslash paths
    const char* win_path = "C:\\Users\\user\\models\\tts\\model.onnx";
    const char* win_sep = find_last_path_separator(win_path);
    EXPECT_TRUE(win_sep != nullptr && std::strcmp(win_sep, "\\model.onnx") == 0);
    EXPECT_TRUE(std::strcmp(filename_from_path(win_path), "model.onnx") == 0);

    // 5. Mixed separators: last forward slash wins
    const char* mixed_fwd_last = "C:\\models/vlm/model.gguf";
    const char* mixed_fwd_sep = find_last_path_separator(mixed_fwd_last);
    EXPECT_TRUE(mixed_fwd_sep != nullptr && std::strcmp(mixed_fwd_sep, "/model.gguf") == 0);
    EXPECT_TRUE(std::strcmp(filename_from_path(mixed_fwd_last), "model.gguf") == 0);

    // 6. Mixed separators: last backslash wins
    const char* mixed_bck_last = "C:/models/vlm\\model.gguf";
    const char* mixed_bck_sep = find_last_path_separator(mixed_bck_last);
    EXPECT_TRUE(mixed_bck_sep != nullptr && std::strcmp(mixed_bck_sep, "\\model.gguf") == 0);
    EXPECT_TRUE(std::strcmp(filename_from_path(mixed_bck_last), "model.gguf") == 0);

    // 7. Trailing separator
    const char* trailing_path = "D:\\folder\\subfolder\\";
    const char* trailing_sep = find_last_path_separator(trailing_path);
    EXPECT_TRUE(trailing_sep != nullptr && std::strcmp(trailing_sep, "\\") == 0);
    EXPECT_TRUE(std::strcmp(filename_from_path(trailing_path), "") == 0);

    // 8. Mutable string truncate-to-parent pattern (VLM module usage)
    char mutable_folder[256];
    std::snprintf(mutable_folder, sizeof(mutable_folder), "C:\\models\\vlm\\model.gguf");
    char* sep = find_last_path_separator(mutable_folder);
    EXPECT_TRUE(sep != nullptr);
    if (sep) {
        *sep = '\0';
    }
    EXPECT_TRUE(std::strcmp(mutable_folder, "C:\\models\\vlm") == 0);

    // 9. Root-level path parent derivation (POSIX and Windows root preservation)
    char posix_root[64] = "/model.gguf";
    char* posix_root_sep = find_last_path_separator(posix_root);
    EXPECT_TRUE(posix_root_sep == posix_root);
    if (posix_root_sep == posix_root) {
        *(posix_root_sep + 1) = '\0';
    }
    EXPECT_TRUE(std::strcmp(posix_root, "/") == 0);

    char win_root[64] = "C:\\model.gguf";
    char* win_root_sep = find_last_path_separator(win_root);
    EXPECT_TRUE(win_root_sep == win_root + 2);
    if (win_root_sep == win_root + 2 && win_root[1] == ':') {
        *(win_root_sep + 1) = '\0';
    }
    EXPECT_TRUE(std::strcmp(win_root, "C:\\") == 0);

    return 0;
}

/**
 * @brief Tests MLX framework directory canonical layout and extraction.
 *
 * @return 0 on success, non-zero on test assertion failure.
 */
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
    if (test_shared_path_separator_helpers() != 0) {
        return 1;
    }
    if (test_mlx_framework_directory_uses_mlx_segment() != 0) {
        return 1;
    }
    std::printf("model path tests passed\n");
    return 0;
}
