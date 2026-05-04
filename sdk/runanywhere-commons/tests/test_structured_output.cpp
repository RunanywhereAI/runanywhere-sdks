/**
 * @file test_structured_output.cpp
 * @brief Focused tests for centralized structured-output helpers.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_structured_output.h"

namespace {

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ_INT(a, b) do { \
    if ((a) != (b)) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %d != %d\n", __FILE__, __LINE__, \
                     static_cast<int>(a), static_cast<int>(b)); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ_STR(actual, expected) do { \
    if (std::strcmp((actual), (expected)) != 0) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d\n  expected: \"%s\"\n  actual:   \"%s\"\n", \
                     __FILE__, __LINE__, (expected), (actual)); \
        return 1; \
    } \
} while (0)

#define ASSERT_SUBSTR(haystack, needle) do { \
    if (std::strstr((haystack), (needle)) == nullptr) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d: '%s' not found in '%.200s'\n", \
                     __FILE__, __LINE__, (needle), (haystack)); \
        return 1; \
    } \
} while (0)

int test_extract_object_from_mixed_text() {
    char* json = nullptr;
    size_t len = 0;
    const rac_result_t rc =
        rac_structured_output_extract_json("prefix {\"ok\":true} suffix", &json, &len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(json != nullptr);
    ASSERT_EQ_STR(json, "{\"ok\":true}");
    ASSERT_EQ_INT(len, std::strlen("{\"ok\":true}"));
    std::free(json);
    return 0;
}

int test_extract_array_with_braces_in_string() {
    char* json = nullptr;
    const rac_result_t rc = rac_structured_output_extract_json(
        "answer [{\"text\":\"brace } inside\"}]", &json, nullptr);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(json != nullptr);
    ASSERT_EQ_STR(json, "[{\"text\":\"brace } inside\"}]");
    std::free(json);
    return 0;
}

int test_validate_success_and_failure() {
    rac_structured_output_validation_t validation{};
    rac_result_t rc =
        rac_structured_output_validate("result {\"value\":42}", nullptr, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_TRUE);
    ASSERT_TRUE(validation.extracted_json != nullptr);
    ASSERT_EQ_STR(validation.extracted_json, "{\"value\":42}");
    rac_structured_output_validation_free(&validation);

    rc = rac_structured_output_validate("no json here", nullptr, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
    ASSERT_TRUE(validation.extracted_json == nullptr);
    ASSERT_TRUE(validation.error_message != nullptr);
    rac_structured_output_validation_free(&validation);
    return 0;
}

int test_prepare_prompt_and_system_prompt() {
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    config.json_schema = "{\"type\":\"object\"}";
    config.include_schema_in_prompt = RAC_TRUE;

    char* prepared = nullptr;
    rac_result_t rc =
        rac_structured_output_prepare_prompt("Return a status", &config, &prepared);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prepared != nullptr);
    ASSERT_SUBSTR(prepared, "Return a status");
    ASSERT_SUBSTR(prepared, "{\"type\":\"object\"}");
    std::free(prepared);

    char* system = nullptr;
    rc = rac_structured_output_get_system_prompt(config.json_schema, &system);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(system != nullptr);
    ASSERT_SUBSTR(system, "outputs ONLY valid JSON");
    ASSERT_SUBSTR(system, "{\"type\":\"object\"}");
    std::free(system);
    return 0;
}

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main() {
    TestCase cases[] = {
        {"extract_object_from_mixed_text", test_extract_object_from_mixed_text},
        {"extract_array_with_braces_in_string", test_extract_array_with_braces_in_string},
        {"validate_success_and_failure", test_validate_success_and_failure},
        {"prepare_prompt_and_system_prompt", test_prepare_prompt_and_system_prompt},
    };

    int failed = 0;
    const int count = static_cast<int>(sizeof(cases) / sizeof(cases[0]));
    for (int i = 0; i < count; ++i) {
        std::printf("[structured_output] %s ... ", cases[i].name);
        std::fflush(stdout);
        const int rc = cases[i].fn();
        if (rc == 0) {
            std::printf("OK\n");
        } else {
            std::printf("FAIL\n");
            ++failed;
        }
    }
    std::printf("\n[structured_output] %d/%d passed\n", count - failed, count);
    return failed == 0 ? 0 : 1;
}
