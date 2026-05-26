/**
 * @file test_model_heuristics.cpp
 * @brief Tests for CONSOLIDATE-A (CLUSTER-14) commons-owned RAModelInfo
 *        heuristics: tool-call format + parameterCountB + isSmallModel.
 *
 * Exercises the three accessors that replace the duplicated example-side
 * detectors flagged by the reviewer (examples-flutter-005 / 006,
 * examples-ios-003, examples-android-008):
 *
 *   - rac_tool_call_format_from_model_info_proto:
 *       LFM2-Tool variants → RAC_TOOL_FORMAT_LFM2.
 *       Llama-style names  → RAC_TOOL_FORMAT_DEFAULT.
 *       Empty bytes        → RAC_TOOL_FORMAT_DEFAULT.
 *
 *   - rac_model_info_parameter_count_b_proto:
 *       "Qwen2.5 0.5B-Instruct" → 0.5.
 *       "SmolLM2-360M"          → 0.36.
 *       "LFM2-1.2B-Tool"        → 1.2.
 *       Unknown                 → -1.
 *
 *   - rac_model_info_is_small_model_proto:
 *       0.5B / 360M / 0.3B / 500M / 0.6B → RAC_TRUE.
 *       1.2B / 7B / unknown              → RAC_FALSE.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                 \
    do {                                                                                  \
        if (!(cond)) {                                                                    \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

#define ASSERT_EQ_INT(a, b)                                                             \
    do {                                                                                \
        if ((a) != (b)) {                                                               \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %d != %d\n", __FILE__, __LINE__, \
                         static_cast<int>(a), static_cast<int>(b));                     \
            return 1;                                                                   \
        }                                                                               \
    } while (0)

#define ASSERT_NEAR(actual, expected, tol)                                                 \
    do {                                                                                   \
        const float __a = (actual);                                                        \
        const float __e = (expected);                                                      \
        const float __d = __a - __e;                                                       \
        const float __abs = __d < 0.0f ? -__d : __d;                                       \
        if (__abs > (tol)) {                                                               \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: |%f - %f| > %f\n", __FILE__,        \
                         __LINE__, __a, __e, (tol));                                       \
            return 1;                                                                      \
        }                                                                                  \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

std::vector<uint8_t> serialize_model_info(const std::string& id, const std::string& name,
                                          const std::string& description = "") {
    runanywhere::v1::ModelInfo m;
    m.set_id(id);
    m.set_name(name);
    if (!description.empty()) {
        m.set_description(description);
    }
    std::vector<uint8_t> out(m.ByteSizeLong());
    (void)m.SerializeToArray(out.data(), static_cast<int>(out.size()));
    return out;
}

int test_tool_call_format_lfm2_tool_variants() {
    const char* lfm2_names[] = {
        "LFM2-1.2B-Tool",
        "LFM2-350M-Tool",
        "LiquidAI/LFM2-1.2B-Tool",
        "lfm2-tool-1.2b",
    };
    for (const char* name : lfm2_names) {
        const auto bytes = serialize_model_info("test-id", name);
        rac_tool_call_format_t f = RAC_TOOL_FORMAT_DEFAULT;
        rac_result_t rc = rac_tool_call_format_from_model_info_proto(
            bytes.data(), bytes.size(), &f);
        if (rc != RAC_SUCCESS) {
            std::fprintf(stderr, "rc != SUCCESS for name=%s rc=%d\n", name, (int)rc);
            return 1;
        }
        if (f != RAC_TOOL_FORMAT_LFM2) {
            std::fprintf(stderr, "expected LFM2 for name=%s got=%d\n", name, (int)f);
            return 1;
        }
    }
    return 0;
}

int test_tool_call_format_non_lfm2_defaults_to_json() {
    const char* default_names[] = {
        "Qwen2.5-0.5B-Instruct",
        "Llama-3.2-3B-Instruct",
        "LFM2-1.2B",   // LFM2 base (no Tool variant) stays on default JSON.
        "tool-router", // contains "tool" but no "lfm2".
        "",            // empty name → default.
    };
    for (const char* name : default_names) {
        const auto bytes = serialize_model_info("test-id", name);
        rac_tool_call_format_t f = RAC_TOOL_FORMAT_LFM2;  // intentional non-default sentinel.
        rac_result_t rc = rac_tool_call_format_from_model_info_proto(
            bytes.data(), bytes.size(), &f);
        if (rc != RAC_SUCCESS) {
            std::fprintf(stderr, "rc != SUCCESS for name=%s rc=%d\n", name, (int)rc);
            return 1;
        }
        if (f != RAC_TOOL_FORMAT_DEFAULT) {
            std::fprintf(stderr, "expected DEFAULT for name=%s got=%d\n", name, (int)f);
            return 1;
        }
    }
    return 0;
}

int test_tool_call_format_uses_id_and_description() {
    // Reviewer evidence: examples lowercased and concatenated multiple model
    // identity sources. Verify that id-only and description-only matches both
    // resolve to LFM2.
    {
        const auto bytes = serialize_model_info("liquidai/LFM2-1.2B-Tool", "");
        rac_tool_call_format_t f = RAC_TOOL_FORMAT_DEFAULT;
        ASSERT_EQ_INT(rac_tool_call_format_from_model_info_proto(bytes.data(), bytes.size(), &f),
                      RAC_SUCCESS);
        ASSERT_EQ_INT(f, RAC_TOOL_FORMAT_LFM2);
    }
    {
        const auto bytes =
            serialize_model_info("", "", "Liquid AI LFM2 Tool-calling preview");
        rac_tool_call_format_t f = RAC_TOOL_FORMAT_DEFAULT;
        ASSERT_EQ_INT(rac_tool_call_format_from_model_info_proto(bytes.data(), bytes.size(), &f),
                      RAC_SUCCESS);
        ASSERT_EQ_INT(f, RAC_TOOL_FORMAT_LFM2);
    }
    return 0;
}

int test_tool_call_format_handles_empty_bytes() {
    rac_tool_call_format_t f = RAC_TOOL_FORMAT_LFM2;  // non-default sentinel.
    ASSERT_EQ_INT(rac_tool_call_format_from_model_info_proto(nullptr, 0, &f), RAC_SUCCESS);
    ASSERT_EQ_INT(f, RAC_TOOL_FORMAT_DEFAULT);
    return 0;
}

int test_tool_call_format_null_output_returns_error() {
    ASSERT_EQ_INT(rac_tool_call_format_from_model_info_proto(nullptr, 0, nullptr),
                  RAC_ERROR_NULL_POINTER);
    return 0;
}

int test_tool_call_format_invalid_bytes_returns_decoding_error() {
    // Garbage bytes that do not decode as runanywhere.v1.ModelInfo.
    const uint8_t bad[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    rac_tool_call_format_t f = RAC_TOOL_FORMAT_LFM2;  // non-default sentinel.
    ASSERT_EQ_INT(rac_tool_call_format_from_model_info_proto(bad, sizeof(bad), &f),
                  RAC_ERROR_DECODING_ERROR);
    // Helper still defaults the output on recoverable failure.
    ASSERT_EQ_INT(f, RAC_TOOL_FORMAT_DEFAULT);
    return 0;
}

int test_parameter_count_b_canonical_tokens() {
    struct Sample {
        const char* name;
        float expected;
    };
    const Sample samples[] = {
        {"Qwen2.5-0.5B-Instruct", 0.5f},
        {"Llama 3.2 3B Instruct", 3.0f},
        {"LFM2-1.2B-Tool", 1.2f},
        {"SmolLM2-360M", 0.36f},
        {"phi-mini-3.5b-q4", 3.5f},
        {"some-7b-model", 7.0f},
    };
    for (const auto& s : samples) {
        const auto bytes = serialize_model_info("id", s.name);
        float v = -2.0f;
        rac_result_t rc =
            rac_model_info_parameter_count_b_proto(bytes.data(), bytes.size(), &v);
        if (rc != RAC_SUCCESS) {
            std::fprintf(stderr, "rc != SUCCESS for name=%s rc=%d\n", s.name, (int)rc);
            return 1;
        }
        if (v < s.expected - 0.01f || v > s.expected + 0.01f) {
            std::fprintf(stderr, "expected ~%.3f for name=%s got=%.3f\n", s.expected, s.name, v);
            return 1;
        }
    }
    return 0;
}

int test_parameter_count_b_unknown_returns_negative_one() {
    const auto bytes = serialize_model_info("id", "GenericModel-v1");
    float v = -2.0f;
    ASSERT_EQ_INT(rac_model_info_parameter_count_b_proto(bytes.data(), bytes.size(), &v),
                  RAC_SUCCESS);
    ASSERT_NEAR(v, -1.0f, 0.001f);
    return 0;
}

int test_parameter_count_b_handles_empty_bytes() {
    float v = 99.0f;
    ASSERT_EQ_INT(rac_model_info_parameter_count_b_proto(nullptr, 0, &v), RAC_SUCCESS);
    ASSERT_NEAR(v, -1.0f, 0.001f);
    return 0;
}

int test_is_small_model_below_threshold() {
    const char* small_names[] = {
        "Qwen2.5-0.5B-Instruct",
        "SmolLM2-360M",
        "LFM2-350M-Tool",
        "qwen-0.6b",
        "test-0.3b",
        "test-500m",
    };
    for (const char* name : small_names) {
        const auto bytes = serialize_model_info("id", name);
        rac_bool_t is_small = RAC_FALSE;
        ASSERT_EQ_INT(
            rac_model_info_is_small_model_proto(bytes.data(), bytes.size(), &is_small),
            RAC_SUCCESS);
        if (is_small != RAC_TRUE) {
            std::fprintf(stderr, "expected RAC_TRUE for name=%s\n", name);
            return 1;
        }
    }
    return 0;
}

int test_is_small_model_above_threshold() {
    const char* large_names[] = {
        "LFM2-1.2B-Tool",
        "Llama-3.2-3B-Instruct",
        "Mistral-7B",
        "GenericModel-v1",  // unknown → RAC_FALSE.
    };
    for (const char* name : large_names) {
        const auto bytes = serialize_model_info("id", name);
        rac_bool_t is_small = RAC_TRUE;
        ASSERT_EQ_INT(
            rac_model_info_is_small_model_proto(bytes.data(), bytes.size(), &is_small),
            RAC_SUCCESS);
        if (is_small != RAC_FALSE) {
            std::fprintf(stderr, "expected RAC_FALSE for name=%s\n", name);
            return 1;
        }
    }
    return 0;
}

int test_is_small_model_null_output_returns_error() {
    ASSERT_EQ_INT(rac_model_info_is_small_model_proto(nullptr, 0, nullptr),
                  RAC_ERROR_NULL_POINTER);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    int failures = 0;
#ifdef RAC_HAVE_PROTOBUF
    failures += test_tool_call_format_lfm2_tool_variants();
    failures += test_tool_call_format_non_lfm2_defaults_to_json();
    failures += test_tool_call_format_uses_id_and_description();
    failures += test_tool_call_format_handles_empty_bytes();
    failures += test_tool_call_format_null_output_returns_error();
    failures += test_tool_call_format_invalid_bytes_returns_decoding_error();
    failures += test_parameter_count_b_canonical_tokens();
    failures += test_parameter_count_b_unknown_returns_negative_one();
    failures += test_parameter_count_b_handles_empty_bytes();
    failures += test_is_small_model_below_threshold();
    failures += test_is_small_model_above_threshold();
    failures += test_is_small_model_null_output_returns_error();
#else
    std::fprintf(stderr,
                 "test_model_heuristics: RAC_HAVE_PROTOBUF not defined; skipping behavioural "
                 "tests (commons builds without protobuf are header-only here).\n");
#endif
    if (failures == 0) {
        std::fprintf(stderr, "test_model_heuristics: ALL PASS\n");
    } else {
        std::fprintf(stderr, "test_model_heuristics: %d FAILURE(S)\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
