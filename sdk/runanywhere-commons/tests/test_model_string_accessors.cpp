/**
 * @file test_model_string_accessors.cpp
 * @brief Parity tests for the canonical wire-string / display / analytics
 *        accessors over rac_model_format_t and rac_inference_framework_t.
 *
 * These accessors centralize per-SDK switch tables (Swift's ~400-LOC
 * RAModelFormat / RAInferenceFramework extensions in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift`).
 * The tests below confirm:
 *
 *   - Every enum value in both rac_model_format_t and rac_inference_framework_t
 *     yields a non-empty wire/display/analytics string.
 *   - Wire strings match the proto enum names from idl/model_types.proto
 *     (matches what swift-protobuf emits during JSON encoding).
 *   - Round-trip for inference frameworks: wire_string(value) → from_string
 *     reproduces the original value, and display_name / analytics_key inputs
 *     also parse back to the original (case-insensitive).
 *   - NULL out-pointer rejection (RAC_ERROR_NULL_POINTER).
 *   - Unknown input strings yield RAC_ERROR_NOT_FOUND with the out parameter
 *     reset to RAC_FRAMEWORK_UNKNOWN.
 */

#include <cstdio>
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

#define EXPECT_NONEMPTY(_str)                                                              \
    do {                                                                                   \
        if (!(_str) || (_str)[0] == '\0') {                                                \
            std::fprintf(stderr, "FAIL @ %s:%d: empty/null string\n", __FILE__, __LINE__); \
            return 1;                                                                      \
        }                                                                                  \
    } while (0)

// All enum values exposed by rac_model_format_t.
constexpr rac_model_format_t kAllFormats[] = {
    RAC_MODEL_FORMAT_UNSPECIFIED, RAC_MODEL_FORMAT_GGUF,        RAC_MODEL_FORMAT_GGML,
    RAC_MODEL_FORMAT_ONNX,        RAC_MODEL_FORMAT_ORT,         RAC_MODEL_FORMAT_BIN,
    RAC_MODEL_FORMAT_COREML,      RAC_MODEL_FORMAT_MLMODEL,     RAC_MODEL_FORMAT_MLPACKAGE,
    RAC_MODEL_FORMAT_TFLITE,      RAC_MODEL_FORMAT_SAFETENSORS, RAC_MODEL_FORMAT_QNN_CONTEXT,
    RAC_MODEL_FORMAT_ZIP,         RAC_MODEL_FORMAT_FOLDER,      RAC_MODEL_FORMAT_PROPRIETARY,
    RAC_MODEL_FORMAT_UNKNOWN,
};

// All enum values exposed by rac_inference_framework_t.
constexpr rac_inference_framework_t kAllFrameworks[] = {
    RAC_FRAMEWORK_ONNX,
    RAC_FRAMEWORK_LLAMACPP,
    RAC_FRAMEWORK_FOUNDATION_MODELS,
    RAC_FRAMEWORK_SYSTEM_TTS,
    RAC_FRAMEWORK_FLUID_AUDIO,
    RAC_FRAMEWORK_BUILTIN,
    RAC_FRAMEWORK_NONE,
    RAC_FRAMEWORK_MLX,
    RAC_FRAMEWORK_COREML,
    RAC_FRAMEWORK_METALRT,
    RAC_FRAMEWORK_GENIE,
    RAC_FRAMEWORK_SHERPA,
    RAC_FRAMEWORK_UNKNOWN,
};

// Every model format yields a non-empty proto-style wire string.
int test_model_format_wire_string_nonempty() {
    for (rac_model_format_t f : kAllFormats) {
        const char* s = nullptr;
        EXPECT_RC(rac_model_format_wire_string(f, &s), RAC_SUCCESS);
        EXPECT_NONEMPTY(s);
        // Proto enum names always start with the enum's MODEL_FORMAT_ prefix.
        EXPECT_TRUE(std::strncmp(s, "MODEL_FORMAT_", 13) == 0);
    }
    return 0;
}

// Spot-check the canonical proto enum names for a few formats.
int test_model_format_wire_string_canonical_names() {
    const char* s = nullptr;
    EXPECT_RC(rac_model_format_wire_string(RAC_MODEL_FORMAT_GGUF, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "MODEL_FORMAT_GGUF") == 0);

    EXPECT_RC(rac_model_format_wire_string(RAC_MODEL_FORMAT_ONNX, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "MODEL_FORMAT_ONNX") == 0);

    EXPECT_RC(rac_model_format_wire_string(RAC_MODEL_FORMAT_QNN_CONTEXT, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "MODEL_FORMAT_QNN_CONTEXT") == 0);

    EXPECT_RC(rac_model_format_wire_string(RAC_MODEL_FORMAT_UNKNOWN, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "MODEL_FORMAT_UNKNOWN") == 0);

    return 0;
}

// Every inference framework value yields non-empty wire/display/analytics.
// Spot-check the canonical proto wire string mapping
// (RAC_FRAMEWORK_LLAMACPP → "INFERENCE_FRAMEWORK_LLAMA_CPP").
int test_inference_framework_strings_nonempty() {
    for (rac_inference_framework_t fw : kAllFrameworks) {
        const char* wire = nullptr;
        const char* display = nullptr;
        const char* key = nullptr;

        EXPECT_RC(rac_inference_framework_wire_string(fw, &wire), RAC_SUCCESS);
        EXPECT_NONEMPTY(wire);
        EXPECT_TRUE(std::strncmp(wire, "INFERENCE_FRAMEWORK_", 20) == 0);

        EXPECT_RC(rac_inference_framework_display_name(fw, &display), RAC_SUCCESS);
        EXPECT_NONEMPTY(display);

        EXPECT_RC(rac_inference_framework_analytics_key(fw, &key), RAC_SUCCESS);
        EXPECT_NONEMPTY(key);
    }
    return 0;
}

int test_inference_framework_canonical_names() {
    const char* s = nullptr;
    EXPECT_RC(rac_inference_framework_wire_string(RAC_FRAMEWORK_LLAMACPP, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "INFERENCE_FRAMEWORK_LLAMA_CPP") == 0);

    EXPECT_RC(rac_inference_framework_wire_string(RAC_FRAMEWORK_FOUNDATION_MODELS, &s),
              RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "INFERENCE_FRAMEWORK_FOUNDATION_MODELS") == 0);

    EXPECT_RC(rac_inference_framework_wire_string(RAC_FRAMEWORK_BUILTIN, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "INFERENCE_FRAMEWORK_BUILT_IN") == 0);

    EXPECT_RC(rac_inference_framework_display_name(RAC_FRAMEWORK_LLAMACPP, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "llama.cpp") == 0);

    EXPECT_RC(rac_inference_framework_display_name(RAC_FRAMEWORK_COREML, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "Core ML") == 0);

    EXPECT_RC(rac_inference_framework_analytics_key(RAC_FRAMEWORK_LLAMACPP, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "llama_cpp") == 0);

    EXPECT_RC(rac_inference_framework_analytics_key(RAC_FRAMEWORK_BUILTIN, &s), RAC_SUCCESS);
    EXPECT_TRUE(std::strcmp(s, "built_in") == 0);

    return 0;
}

// Round-trip: wire_string(value) → from_string yields the original value, for
// every framework value.
int test_inference_framework_wire_round_trip() {
    for (rac_inference_framework_t fw : kAllFrameworks) {
        const char* wire = nullptr;
        EXPECT_RC(rac_inference_framework_wire_string(fw, &wire), RAC_SUCCESS);
        EXPECT_NONEMPTY(wire);

        rac_inference_framework_t parsed = RAC_FRAMEWORK_UNKNOWN;
        EXPECT_RC(rac_inference_framework_from_string(wire, &parsed), RAC_SUCCESS);
        EXPECT_TRUE(parsed == fw);
    }
    return 0;
}

// from_string also accepts analytics keys and display names (case-insensitive).
int test_inference_framework_from_string_alias_inputs() {
    rac_inference_framework_t parsed = RAC_FRAMEWORK_UNKNOWN;

    // Analytics key
    EXPECT_RC(rac_inference_framework_from_string("llama_cpp", &parsed), RAC_SUCCESS);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_LLAMACPP);

    // Display name
    EXPECT_RC(rac_inference_framework_from_string("llama.cpp", &parsed), RAC_SUCCESS);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_LLAMACPP);

    // Display name with different casing
    EXPECT_RC(rac_inference_framework_from_string("CORE ML", &parsed), RAC_SUCCESS);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_COREML);

    // Wire string with mixed casing (Swift's caseInsensitive init guarantees this).
    EXPECT_RC(rac_inference_framework_from_string("inference_framework_onnx", &parsed),
              RAC_SUCCESS);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_ONNX);

    return 0;
}

// Unknown / nonsense input → NOT_FOUND, out-param reset to UNKNOWN.
int test_inference_framework_from_string_unknown() {
    rac_inference_framework_t parsed = RAC_FRAMEWORK_LLAMACPP;  // sentinel

    EXPECT_RC(rac_inference_framework_from_string("not_a_framework", &parsed), RAC_ERROR_NOT_FOUND);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_UNKNOWN);

    parsed = RAC_FRAMEWORK_LLAMACPP;
    EXPECT_RC(rac_inference_framework_from_string("", &parsed), RAC_ERROR_NOT_FOUND);
    EXPECT_TRUE(parsed == RAC_FRAMEWORK_UNKNOWN);

    return 0;
}

// NULL out-pointer rejection.
int test_null_out_pointer_rejection() {
    EXPECT_RC(rac_model_format_wire_string(RAC_MODEL_FORMAT_GGUF, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_inference_framework_wire_string(RAC_FRAMEWORK_LLAMACPP, nullptr),
              RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_inference_framework_display_name(RAC_FRAMEWORK_LLAMACPP, nullptr),
              RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_inference_framework_analytics_key(RAC_FRAMEWORK_LLAMACPP, nullptr),
              RAC_ERROR_NULL_POINTER);

    rac_inference_framework_t out = RAC_FRAMEWORK_UNKNOWN;
    EXPECT_RC(rac_inference_framework_from_string(nullptr, &out), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_inference_framework_from_string("llama.cpp", nullptr), RAC_ERROR_NULL_POINTER);

    return 0;
}

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    int failures = 0;
    failures += test_model_format_wire_string_nonempty();
    failures += test_model_format_wire_string_canonical_names();
    failures += test_inference_framework_strings_nonempty();
    failures += test_inference_framework_canonical_names();
    failures += test_inference_framework_wire_round_trip();
    failures += test_inference_framework_from_string_alias_inputs();
    failures += test_inference_framework_from_string_unknown();
    failures += test_null_out_pointer_rejection();

    if (failures == 0) {
        std::fprintf(stdout, "[PASS] test_model_string_accessors\n");
        return 0;
    }
    std::fprintf(stderr, "[FAIL] test_model_string_accessors (%d failure(s))\n", failures);
    return 1;
}
