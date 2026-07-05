/**
 * @file test_model_format_for_framework.cpp
 * @brief Parity tests for rac_model_format_for_framework().
 *
 * The new commons-owned helper centralizes the per-framework "is this
 * extension a model file?" check that each platform SDK previously
 * supplied via a platform discovery-callback struct (Swift's
 * racIsModelFile). Mirrors the Swift reference table 1:1.
 *
 * Cases covered:
 *   - Positive matches per framework (.gguf + LLAMACPP, .onnx + ONNX, …)
 *   - Negative cross-framework rejection (.gguf + ONNX → false)
 *   - Unknown / nonsense extensions (.foo → false for every framework)
 *   - Case-insensitivity ("GGUF", "Gguf", ".GGUF" all accepted)
 *   - Leading-dot tolerance (".gguf" and "gguf" both accepted)
 *   - Builtin-style frameworks (Foundation Models, System TTS) always true
 *   - NULL out-pointer rejected with RAC_ERROR_NULL_POINTER
 *   - NULL extension does not crash; non-builtin frameworks return false
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
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

// Helper: invoke the API and assert it returns SUCCESS, return the bool.
bool query(rac_inference_framework_t fw, const char* ext) {
    rac_bool_t out = RAC_FALSE;
    rac_result_t rc = rac_model_format_for_framework(fw, ext, &out);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_model_format_for_framework returned rc=%d\n", rc);
        std::abort();
    }
    return out == RAC_TRUE;
}

// Positive matches per framework.
int test_positive_matches() {
    // LLAMACPP: .gguf, .bin
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, ".gguf"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, "gguf"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, ".bin"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, "bin"));

    // ONNX / SHERPA: .onnx, .ort
    EXPECT_TRUE(query(RAC_FRAMEWORK_ONNX, ".onnx"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_ONNX, "onnx"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_ONNX, ".ort"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_SHERPA, "onnx"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_SHERPA, ".ort"));

    // CoreML: .mlmodelc, .mlpackage, .mlmodel
    EXPECT_TRUE(query(RAC_FRAMEWORK_COREML, "mlmodelc"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_COREML, ".mlpackage"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_COREML, "mlmodel"));

    // MetalRT: .safetensors, .json
    EXPECT_TRUE(query(RAC_FRAMEWORK_METALRT, "safetensors"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_METALRT, ".safetensors"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_METALRT, "json"));

    return 0;
}

// Negative cross-framework rejection.
int test_negative_cross_framework() {
    // .gguf is NOT a model file for ONNX
    EXPECT_TRUE(!query(RAC_FRAMEWORK_ONNX, "gguf"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_ONNX, ".gguf"));

    // .onnx is NOT a model file for LLAMACPP
    EXPECT_TRUE(!query(RAC_FRAMEWORK_LLAMACPP, "onnx"));

    // .safetensors is NOT a model file for ONNX
    EXPECT_TRUE(!query(RAC_FRAMEWORK_ONNX, "safetensors"));

    // .mlmodelc is NOT a model file for LLAMACPP
    EXPECT_TRUE(!query(RAC_FRAMEWORK_LLAMACPP, "mlmodelc"));

    // .json is NOT a model file for ONNX (only MetalRT accepts it)
    EXPECT_TRUE(!query(RAC_FRAMEWORK_ONNX, "json"));

    return 0;
}

// Unknown / nonsense extensions.
int test_unknown_extensions() {
    EXPECT_TRUE(!query(RAC_FRAMEWORK_LLAMACPP, "foo"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_ONNX, ".bar"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_COREML, "qux"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_METALRT, "txt"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_SHERPA, ""));  // empty string

    return 0;
}

// Case-insensitivity.
int test_case_insensitivity() {
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, "GGUF"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, ".GGUF"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_LLAMACPP, "Gguf"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_ONNX, "ONNX"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_ONNX, ".ONNX"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_COREML, "MLMODELC"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_METALRT, "SafeTensors"));
    return 0;
}

// Builtin-style frameworks always claim membership.
int test_builtin_frameworks() {
    // Foundation Models / System TTS are builtin:// — no on-disk artifact,
    // so any extension (or none) reports true.
    EXPECT_TRUE(query(RAC_FRAMEWORK_FOUNDATION_MODELS, ".gguf"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_FOUNDATION_MODELS, "anything"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_FOUNDATION_MODELS, ""));
    EXPECT_TRUE(query(RAC_FRAMEWORK_FOUNDATION_MODELS, nullptr));

    EXPECT_TRUE(query(RAC_FRAMEWORK_SYSTEM_TTS, "anything"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_SYSTEM_TTS, nullptr));
    return 0;
}

// NULL out-pointer rejection.
int test_null_out_pointer() {
    EXPECT_RC(rac_model_format_for_framework(RAC_FRAMEWORK_LLAMACPP, ".gguf", nullptr),
              RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_format_for_framework(RAC_FRAMEWORK_FOUNDATION_MODELS, "anything", nullptr),
              RAC_ERROR_NULL_POINTER);
    return 0;
}

// NULL extension on a non-builtin framework returns false (not an error).
int test_null_extension_non_builtin() {
    rac_bool_t out = RAC_TRUE;  // sentinel — should be set to RAC_FALSE
    EXPECT_RC(rac_model_format_for_framework(RAC_FRAMEWORK_LLAMACPP, nullptr, &out), RAC_SUCCESS);
    EXPECT_TRUE(out == RAC_FALSE);

    out = RAC_TRUE;
    EXPECT_RC(rac_model_format_for_framework(RAC_FRAMEWORK_ONNX, nullptr, &out), RAC_SUCCESS);
    EXPECT_TRUE(out == RAC_FALSE);
    return 0;
}

// Default fallback for less-enumerated frameworks (UNKNOWN, BUILTIN, NONE,
// MLX) follows the permissive Swift fallback arm — accepts the common
// model extensions but rejects unknown ones.
int test_unknown_framework_fallback() {
    EXPECT_TRUE(query(RAC_FRAMEWORK_UNKNOWN, "gguf"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_UNKNOWN, "onnx"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_UNKNOWN, "bin"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_UNKNOWN, "ort"));
    EXPECT_TRUE(query(RAC_FRAMEWORK_UNKNOWN, "mlmodelc"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_UNKNOWN, "safetensors"));
    EXPECT_TRUE(!query(RAC_FRAMEWORK_UNKNOWN, "foo"));
    return 0;
}

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    int failures = 0;
    failures += test_positive_matches();
    failures += test_negative_cross_framework();
    failures += test_unknown_extensions();
    failures += test_case_insensitivity();
    failures += test_builtin_frameworks();
    failures += test_null_out_pointer();
    failures += test_null_extension_non_builtin();
    failures += test_unknown_framework_fallback();

    if (failures == 0) {
        std::fprintf(stdout, "[PASS] test_model_format_for_framework\n");
        return 0;
    }
    std::fprintf(stderr, "[FAIL] test_model_format_for_framework (%d failure(s))\n", failures);
    return 1;
}
