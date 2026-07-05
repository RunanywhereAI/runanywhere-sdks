/**
 * @file test_model_types_mappers.cpp
 * @brief Round-trip parity tests for proto enum ↔ C enum mappers
 *        (T15a / SWIFT-DUP-MODELTYPES-COMPUTED).
 *
 * Exercises the 6 mapper pairs in
 * sdk/runanywhere-commons/src/infrastructure/model_management/model_types_mappers.cpp:
 *
 *   - InferenceFramework  ↔ rac_inference_framework_t
 *   - ModelCategory       ↔ rac_model_category_t
 *   - ModelFormat         ↔ rac_model_format_t
 *   - ModelSource         ↔ rac_model_source_t
 *   - ArchiveType         ↔ rac_archive_type_t
 *   - ArchiveStructure    ↔ rac_archive_structure_t
 *
 * For each pair the test:
 *   - Round-trips every defined enum value: proto → C → proto and
 *     C → proto → C, asserting the identity (or documented mapping for the
 *     few asymmetric cases like proto UNSPECIFIED → C UNKNOWN).
 *   - Verifies that out-of-range proto values yield RAC_ERROR_INVALID_ARGUMENT
 *     with the out parameter reset to a safe default.
 *   - Verifies NULL out-pointer rejection (RAC_ERROR_NULL_POINTER).
 */

#include <cstdint>
#include <cstdio>

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

// Reference proto integer values (mirrors idl/model_types.proto).
// Kept locally so the test file does not depend on the generated *.pb.h.

// InferenceFramework — proto range 0..23 minus the retired values 8
// (WHISPERKIT_COREML), 17 (WHISPERKIT), and 18 (OPENAI_WHISPER), which are no
// longer defined in the proto and therefore map to RAC_ERROR_INVALID_ARGUMENT.
constexpr int32_t kProtoIfwAll[] = {
    0,   // UNSPECIFIED        → RAC_FRAMEWORK_UNKNOWN
    1,   // ONNX               → RAC_FRAMEWORK_ONNX
    2,   // LLAMA_CPP          → RAC_FRAMEWORK_LLAMACPP
    3,   // FOUNDATION_MODELS  → RAC_FRAMEWORK_FOUNDATION_MODELS
    4,   // SYSTEM_TTS         → RAC_FRAMEWORK_SYSTEM_TTS
    5,   // FLUID_AUDIO        → RAC_FRAMEWORK_FLUID_AUDIO
    6,   // COREML             → RAC_FRAMEWORK_COREML
    7,   // MLX                → RAC_FRAMEWORK_MLX
    9,   // METALRT            → RAC_FRAMEWORK_METALRT
    10,  // GENIE              → RAC_FRAMEWORK_GENIE
    11,  // TFLITE             → RAC_FRAMEWORK_UNKNOWN (no C case)
    12,  // EXECUTORCH         → RAC_FRAMEWORK_UNKNOWN
    13,  // MEDIAPIPE          → RAC_FRAMEWORK_UNKNOWN
    14,  // MLC                → RAC_FRAMEWORK_UNKNOWN
    15,  // PICO_LLM           → RAC_FRAMEWORK_UNKNOWN
    16,  // PIPER_TTS          → RAC_FRAMEWORK_UNKNOWN
    19,  // SWIFT_TRANSFORMERS → RAC_FRAMEWORK_UNKNOWN
    20,  // BUILT_IN           → RAC_FRAMEWORK_BUILTIN
    21,  // NONE               → RAC_FRAMEWORK_NONE
    22,  // UNKNOWN            → RAC_FRAMEWORK_UNKNOWN
    23,  // SHERPA             → RAC_FRAMEWORK_SHERPA
};

// All defined C inference framework values.
constexpr rac_inference_framework_t kCAllFrameworks[] = {
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

// ModelCategory — proto 0..9.
constexpr int32_t kProtoMcAll[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};

constexpr rac_model_category_t kCAllCategories[] = {
    RAC_MODEL_CATEGORY_LANGUAGE,
    RAC_MODEL_CATEGORY_SPEECH_RECOGNITION,
    RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS,
    RAC_MODEL_CATEGORY_VISION,
    RAC_MODEL_CATEGORY_IMAGE_GENERATION,
    RAC_MODEL_CATEGORY_MULTIMODAL,
    RAC_MODEL_CATEGORY_AUDIO,
    RAC_MODEL_CATEGORY_EMBEDDING,
    RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    RAC_MODEL_CATEGORY_UNKNOWN,
};

// ModelFormat — proto 0..15.
constexpr int32_t kProtoMfAll[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};

constexpr rac_model_format_t kCAllFormats[] = {
    RAC_MODEL_FORMAT_UNSPECIFIED, RAC_MODEL_FORMAT_GGUF,        RAC_MODEL_FORMAT_GGML,
    RAC_MODEL_FORMAT_ONNX,        RAC_MODEL_FORMAT_ORT,         RAC_MODEL_FORMAT_BIN,
    RAC_MODEL_FORMAT_COREML,      RAC_MODEL_FORMAT_MLMODEL,     RAC_MODEL_FORMAT_MLPACKAGE,
    RAC_MODEL_FORMAT_TFLITE,      RAC_MODEL_FORMAT_SAFETENSORS, RAC_MODEL_FORMAT_QNN_CONTEXT,
    RAC_MODEL_FORMAT_ZIP,         RAC_MODEL_FORMAT_FOLDER,      RAC_MODEL_FORMAT_PROPRIETARY,
    RAC_MODEL_FORMAT_UNKNOWN,
};

// ModelSource — proto 0..3.
constexpr int32_t kProtoMsAll[] = {0, 1, 2, 3};

constexpr rac_model_source_t kCAllSources[] = {
    RAC_MODEL_SOURCE_REMOTE,
    RAC_MODEL_SOURCE_LOCAL,
};

// ArchiveType — proto 0..4.
constexpr int32_t kProtoAtAll[] = {0, 1, 2, 3, 4};

constexpr rac_archive_type_t kCAllArchiveTypes[] = {
    RAC_ARCHIVE_TYPE_NONE,   RAC_ARCHIVE_TYPE_ZIP,    RAC_ARCHIVE_TYPE_TAR_BZ2,
    RAC_ARCHIVE_TYPE_TAR_GZ, RAC_ARCHIVE_TYPE_TAR_XZ,
};

// ArchiveStructure — proto 0..4.
constexpr int32_t kProtoAsAll[] = {0, 1, 2, 3, 4};

constexpr rac_archive_structure_t kCAllArchiveStructures[] = {
    RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED,
    RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED,
    RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
    RAC_ARCHIVE_STRUCTURE_UNKNOWN,
};

// InferenceFramework: round-trip every proto value through C and back.
//
// For values 11..16 and 19 (TFLITE/EXECUTORCH/MEDIAPIPE/MLC/PICO_LLM/
// PIPER_TTS/SWIFT_TRANSFORMERS) there is no corresponding C enum case, so the
// from-proto path folds those into RAC_FRAMEWORK_UNKNOWN. The forward direction
// therefore lands on the proto UNKNOWN (=22). We assert that explicitly rather
// than expecting strict identity.
int test_inference_framework_proto_round_trip() {
    for (int32_t proto : kProtoIfwAll) {
        rac_inference_framework_t c = RAC_FRAMEWORK_UNKNOWN;
        EXPECT_RC(rac_inference_framework_from_proto(proto, &c), RAC_SUCCESS);

        int32_t back = -1;
        EXPECT_RC(rac_inference_framework_to_proto(c, &back), RAC_SUCCESS);

        if (proto == 0) {
            // UNSPECIFIED canonically lands at C UNKNOWN, which round-trips to
            // proto UNKNOWN (=22) — not back to UNSPECIFIED.
            EXPECT_TRUE(back == 22);
        } else if (proto >= 11 && proto <= 19) {
            // No C case → folded into UNKNOWN → proto UNKNOWN.
            EXPECT_TRUE(back == 22);
        } else {
            // Every other value has a 1:1 C ↔ proto correspondence.
            EXPECT_TRUE(back == proto);
        }
    }
    return 0;
}

int test_inference_framework_c_round_trip() {
    for (rac_inference_framework_t c : kCAllFrameworks) {
        int32_t proto = -1;
        EXPECT_RC(rac_inference_framework_to_proto(c, &proto), RAC_SUCCESS);

        rac_inference_framework_t back = RAC_FRAMEWORK_ONNX;  // sentinel
        EXPECT_RC(rac_inference_framework_from_proto(proto, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == c);
    }
    return 0;
}

// ModelCategory: every proto value has a 1:1 C correspondence; round-trip
// in both directions must hit the identity.
int test_model_category_proto_round_trip() {
    for (int32_t proto : kProtoMcAll) {
        rac_model_category_t c = RAC_MODEL_CATEGORY_UNKNOWN;
        EXPECT_RC(rac_model_category_from_proto(proto, &c), RAC_SUCCESS);

        int32_t back = -1;
        EXPECT_RC(rac_model_category_to_proto(c, &back), RAC_SUCCESS);

        // proto.UNSPECIFIED (0) → C.UNKNOWN → proto.UNSPECIFIED (0)
        // proto.<defined>      → C.<defined> → proto.<defined>
        EXPECT_TRUE(back == proto);
    }
    return 0;
}

int test_model_category_c_round_trip() {
    for (rac_model_category_t c : kCAllCategories) {
        int32_t proto = -1;
        EXPECT_RC(rac_model_category_to_proto(c, &proto), RAC_SUCCESS);

        rac_model_category_t back = RAC_MODEL_CATEGORY_LANGUAGE;  // sentinel
        EXPECT_RC(rac_model_category_from_proto(proto, &back), RAC_SUCCESS);

        if (c == RAC_MODEL_CATEGORY_UNKNOWN) {
            // C.UNKNOWN → proto.UNSPECIFIED (0) → C.UNKNOWN.
            EXPECT_TRUE(back == RAC_MODEL_CATEGORY_UNKNOWN);
        } else {
            EXPECT_TRUE(back == c);
        }
    }
    return 0;
}

// ModelFormat: values are 1:1 with proto by construction
// (RAC_MODEL_FORMAT_ID_* matches proto integers). The mappers should be
// exact identity for every defined value.
int test_model_format_proto_round_trip() {
    for (int32_t proto : kProtoMfAll) {
        rac_model_format_t c = RAC_MODEL_FORMAT_UNSPECIFIED;
        EXPECT_RC(rac_model_format_from_proto(proto, &c), RAC_SUCCESS);
        EXPECT_TRUE(static_cast<int32_t>(c) == proto);

        int32_t back = -1;
        EXPECT_RC(rac_model_format_to_proto(c, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == proto);
    }
    return 0;
}

int test_model_format_c_round_trip() {
    for (rac_model_format_t c : kCAllFormats) {
        int32_t proto = -1;
        EXPECT_RC(rac_model_format_to_proto(c, &proto), RAC_SUCCESS);
        EXPECT_TRUE(proto == static_cast<int32_t>(c));

        rac_model_format_t back = RAC_MODEL_FORMAT_UNSPECIFIED;
        EXPECT_RC(rac_model_format_from_proto(proto, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == c);
    }
    return 0;
}

// ModelSource: proto has UNSPECIFIED / REMOTE / LOCAL / BUILT_IN.
//   - UNSPECIFIED (0) → C.REMOTE → proto.REMOTE (1).
//   - REMOTE (1)      → C.REMOTE → proto.REMOTE (1).
//   - LOCAL  (2)      → C.LOCAL  → proto.LOCAL  (2).
//   - BUILT_IN (3)    → C.LOCAL  → proto.LOCAL  (2).
int test_model_source_proto_round_trip() {
    for (int32_t proto : kProtoMsAll) {
        rac_model_source_t c = RAC_MODEL_SOURCE_REMOTE;
        EXPECT_RC(rac_model_source_from_proto(proto, &c), RAC_SUCCESS);

        int32_t back = -1;
        EXPECT_RC(rac_model_source_to_proto(c, &back), RAC_SUCCESS);

        if (proto == 0 || proto == 1) {
            EXPECT_TRUE(back == 1);  // both collapse to REMOTE
        } else {
            EXPECT_TRUE(back == 2);  // LOCAL and BUILT_IN both collapse to LOCAL
        }
    }
    return 0;
}

int test_model_source_c_round_trip() {
    for (rac_model_source_t c : kCAllSources) {
        int32_t proto = -1;
        EXPECT_RC(rac_model_source_to_proto(c, &proto), RAC_SUCCESS);

        rac_model_source_t back = RAC_MODEL_SOURCE_REMOTE;
        EXPECT_RC(rac_model_source_from_proto(proto, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == c);
    }
    return 0;
}

// ArchiveType: proto UNSPECIFIED (0) corresponds to C RAC_ARCHIVE_TYPE_NONE
// (-1) — both represent "no archive". Every other value round-trips 1:1.
int test_archive_type_proto_round_trip() {
    for (int32_t proto : kProtoAtAll) {
        rac_archive_type_t c = RAC_ARCHIVE_TYPE_NONE;
        EXPECT_RC(rac_archive_type_from_proto(proto, &c), RAC_SUCCESS);

        int32_t back = -1;
        EXPECT_RC(rac_archive_type_to_proto(c, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == proto);
    }
    return 0;
}

int test_archive_type_c_round_trip() {
    for (rac_archive_type_t c : kCAllArchiveTypes) {
        int32_t proto = -1;
        EXPECT_RC(rac_archive_type_to_proto(c, &proto), RAC_SUCCESS);

        rac_archive_type_t back = RAC_ARCHIVE_TYPE_NONE;
        EXPECT_RC(rac_archive_type_from_proto(proto, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == c);
    }
    return 0;
}

// ArchiveStructure: proto UNSPECIFIED (0) and proto UNKNOWN (4) both fold into
// the C RAC_ARCHIVE_STRUCTURE_UNKNOWN sentinel. The single C UNKNOWN value
// canonicalises forward to proto UNKNOWN (4), not back to UNSPECIFIED. Every
// other value round-trips 1:1.
int test_archive_structure_proto_round_trip() {
    for (int32_t proto : kProtoAsAll) {
        rac_archive_structure_t c = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
        EXPECT_RC(rac_archive_structure_from_proto(proto, &c), RAC_SUCCESS);

        int32_t back = -1;
        EXPECT_RC(rac_archive_structure_to_proto(c, &back), RAC_SUCCESS);

        if (proto == 0) {
            // UNSPECIFIED collapses to C UNKNOWN which forwards to proto UNKNOWN.
            EXPECT_TRUE(back == 4);
        } else {
            EXPECT_TRUE(back == proto);
        }
    }
    return 0;
}

int test_archive_structure_c_round_trip() {
    for (rac_archive_structure_t c : kCAllArchiveStructures) {
        int32_t proto = -1;
        EXPECT_RC(rac_archive_structure_to_proto(c, &proto), RAC_SUCCESS);

        rac_archive_structure_t back = RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
        EXPECT_RC(rac_archive_structure_from_proto(proto, &back), RAC_SUCCESS);
        EXPECT_TRUE(back == c);
    }
    return 0;
}

// Invalid / out-of-range proto values must fail with INVALID_ARGUMENT and
// reset the out parameter to a safe default.
int test_invalid_proto_values() {
    constexpr int32_t kBad[] = {-1, 1000, INT32_MAX};

    for (int32_t bad : kBad) {
        rac_inference_framework_t ifw = RAC_FRAMEWORK_ONNX;
        EXPECT_RC(rac_inference_framework_from_proto(bad, &ifw), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(ifw == RAC_FRAMEWORK_UNKNOWN);

        rac_model_category_t mc = RAC_MODEL_CATEGORY_LANGUAGE;
        EXPECT_RC(rac_model_category_from_proto(bad, &mc), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(mc == RAC_MODEL_CATEGORY_UNKNOWN);

        rac_model_format_t mf = RAC_MODEL_FORMAT_GGUF;
        EXPECT_RC(rac_model_format_from_proto(bad, &mf), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(mf == RAC_MODEL_FORMAT_UNSPECIFIED);

        rac_model_source_t ms = RAC_MODEL_SOURCE_LOCAL;
        EXPECT_RC(rac_model_source_from_proto(bad, &ms), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(ms == RAC_MODEL_SOURCE_REMOTE);

        rac_archive_type_t at = RAC_ARCHIVE_TYPE_ZIP;
        EXPECT_RC(rac_archive_type_from_proto(bad, &at), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(at == RAC_ARCHIVE_TYPE_NONE);

        rac_archive_structure_t as = RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED;
        EXPECT_RC(rac_archive_structure_from_proto(bad, &as), RAC_ERROR_INVALID_ARGUMENT);
        EXPECT_TRUE(as == RAC_ARCHIVE_STRUCTURE_UNKNOWN);
    }
    return 0;
}

// Invalid C enum values (cast from junk ints) must fail with INVALID_ARGUMENT.
int test_invalid_c_values() {
    int32_t out = -1;

    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_inference_framework_to_proto(static_cast<rac_inference_framework_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    out = -1;
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_model_category_to_proto(static_cast<rac_model_category_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    out = -1;
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_model_format_to_proto(static_cast<rac_model_format_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    out = -1;
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_model_source_to_proto(static_cast<rac_model_source_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    out = -1;
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_archive_type_to_proto(static_cast<rac_archive_type_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    out = -1;
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): intentional invalid input
    EXPECT_RC(rac_archive_structure_to_proto(static_cast<rac_archive_structure_t>(12345), &out),
              RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_TRUE(out == 0);

    return 0;
}

// NULL out-pointer rejection across all 10 mappers.
int test_null_out_pointer_rejection() {
    EXPECT_RC(rac_inference_framework_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_inference_framework_to_proto(RAC_FRAMEWORK_ONNX, nullptr),
              RAC_ERROR_NULL_POINTER);

    EXPECT_RC(rac_model_category_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_category_to_proto(RAC_MODEL_CATEGORY_LANGUAGE, nullptr),
              RAC_ERROR_NULL_POINTER);

    EXPECT_RC(rac_model_format_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_format_to_proto(RAC_MODEL_FORMAT_GGUF, nullptr), RAC_ERROR_NULL_POINTER);

    EXPECT_RC(rac_model_source_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_source_to_proto(RAC_MODEL_SOURCE_REMOTE, nullptr), RAC_ERROR_NULL_POINTER);

    EXPECT_RC(rac_archive_type_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_archive_type_to_proto(RAC_ARCHIVE_TYPE_ZIP, nullptr), RAC_ERROR_NULL_POINTER);

    EXPECT_RC(rac_archive_structure_from_proto(1, nullptr), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_archive_structure_to_proto(RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED, nullptr),
              RAC_ERROR_NULL_POINTER);

    return 0;
}

// Spot-check a few specific known mappings.
int test_canonical_mappings() {
    rac_inference_framework_t ifw = RAC_FRAMEWORK_UNKNOWN;
    EXPECT_RC(rac_inference_framework_from_proto(2, &ifw), RAC_SUCCESS);
    EXPECT_TRUE(ifw == RAC_FRAMEWORK_LLAMACPP);

    int32_t proto = -1;
    EXPECT_RC(rac_inference_framework_to_proto(RAC_FRAMEWORK_LLAMACPP, &proto), RAC_SUCCESS);
    EXPECT_TRUE(proto == 2);

    EXPECT_RC(rac_inference_framework_to_proto(RAC_FRAMEWORK_BUILTIN, &proto), RAC_SUCCESS);
    EXPECT_TRUE(proto == 20);  // proto BUILT_IN

    rac_model_category_t mc = RAC_MODEL_CATEGORY_UNKNOWN;
    EXPECT_RC(rac_model_category_from_proto(1, &mc), RAC_SUCCESS);
    EXPECT_TRUE(mc == RAC_MODEL_CATEGORY_LANGUAGE);

    rac_model_format_t mf = RAC_MODEL_FORMAT_UNSPECIFIED;
    EXPECT_RC(rac_model_format_from_proto(1, &mf), RAC_SUCCESS);
    EXPECT_TRUE(mf == RAC_MODEL_FORMAT_GGUF);

    // Proto BUILT_IN (=3) folds to C LOCAL.
    rac_model_source_t ms = RAC_MODEL_SOURCE_REMOTE;
    EXPECT_RC(rac_model_source_from_proto(3, &ms), RAC_SUCCESS);
    EXPECT_TRUE(ms == RAC_MODEL_SOURCE_LOCAL);

    // Proto UNSPECIFIED archive → C NONE.
    rac_archive_type_t at = RAC_ARCHIVE_TYPE_ZIP;
    EXPECT_RC(rac_archive_type_from_proto(0, &at), RAC_SUCCESS);
    EXPECT_TRUE(at == RAC_ARCHIVE_TYPE_NONE);

    // Proto SINGLE_FILE_NESTED (=1) → C SINGLE_FILE_NESTED.
    rac_archive_structure_t as = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
    EXPECT_RC(rac_archive_structure_from_proto(1, &as), RAC_SUCCESS);
    EXPECT_TRUE(as == RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED);

    // Proto UNSPECIFIED archive_structure → C UNKNOWN.
    as = RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED;
    EXPECT_RC(rac_archive_structure_from_proto(0, &as), RAC_SUCCESS);
    EXPECT_TRUE(as == RAC_ARCHIVE_STRUCTURE_UNKNOWN);

    int32_t proto_as = -1;
    EXPECT_RC(rac_archive_structure_to_proto(RAC_ARCHIVE_STRUCTURE_UNKNOWN, &proto_as),
              RAC_SUCCESS);
    EXPECT_TRUE(proto_as == 4);

    return 0;
}

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    int failures = 0;
    failures += test_inference_framework_proto_round_trip();
    failures += test_inference_framework_c_round_trip();
    failures += test_model_category_proto_round_trip();
    failures += test_model_category_c_round_trip();
    failures += test_model_format_proto_round_trip();
    failures += test_model_format_c_round_trip();
    failures += test_model_source_proto_round_trip();
    failures += test_model_source_c_round_trip();
    failures += test_archive_type_proto_round_trip();
    failures += test_archive_type_c_round_trip();
    failures += test_archive_structure_proto_round_trip();
    failures += test_archive_structure_c_round_trip();
    failures += test_invalid_proto_values();
    failures += test_invalid_c_values();
    failures += test_null_out_pointer_rejection();
    failures += test_canonical_mappings();

    if (failures == 0) {
        std::fprintf(stdout, "[PASS] test_model_types_mappers\n");
        return 0;
    }
    std::fprintf(stderr, "[FAIL] test_model_types_mappers (%d failure(s))\n", failures);
    return 1;
}
