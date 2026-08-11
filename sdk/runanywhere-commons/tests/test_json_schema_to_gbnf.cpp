/**
 * @file test_json_schema_to_gbnf.cpp
 * @brief Characterization tests for commons-owned JSON Schema → GBNF + repair.
 */

#include <cstdio>
#include <cstring>
#include <string>

#include "features/llm/json_schema_to_gbnf_internal.h"

namespace {

#define ASSERT_TRUE(cond)                                                                 \
    do {                                                                                  \
        if (!(cond)) {                                                                    \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

#define ASSERT_SUBSTR(haystack, needle)                                                         \
    do {                                                                                        \
        if ((haystack).find(needle) == std::string::npos) {                                     \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: '%s' not found in '%.200s'\n", __FILE__, \
                         __LINE__, (needle), (haystack).c_str());                               \
            return 1;                                                                           \
        }                                                                                       \
    } while (0)

int test_object_schema_compiles() {
    std::string grammar;
    std::string error;
    ASSERT_TRUE(rac::llm::json_schema_to_gbnf(
        R"({"type":"object","properties":{"name":{"type":"string"},"age":{"type":"integer"}}})",
        &grammar, &error));
    ASSERT_TRUE(error.empty());
    ASSERT_SUBSTR(grammar, "root ::=");
    ASSERT_SUBSTR(grammar, "obj0 ::=");
    ASSERT_SUBSTR(grammar, "integer ::=");
    ASSERT_SUBSTR(grammar, "string ::=");
    return 0;
}

int test_invalid_json_fails() {
    std::string grammar;
    std::string error;
    ASSERT_TRUE(!rac::llm::json_schema_to_gbnf("{not-json", &grammar, &error));
    ASSERT_TRUE(!error.empty());
    return 0;
}

int test_max_items_nested_optional_tails() {
    std::string grammar;
    ASSERT_TRUE(rac::llm::json_schema_to_gbnf(
        R"({"type":"array","items":{"type":"string"},"maxItems":2})", &grammar, nullptr));
    ASSERT_SUBSTR(grammar, "arr0t1 ::=");
    ASSERT_SUBSTR(grammar, "arr0t2 ::=");
    ASSERT_SUBSTR(grammar, "arr0 ::= \"[\" ws ( arr0t2 )? ws \"]\"");
    return 0;
}

int test_repair_prompt_is_deterministic() {
    const std::string prompt = rac::llm::structured_output_repair_prompt(
        "Extract the person", "{\"name\":1}",
        R"({"type":"object","properties":{"name":{"type":"string"}}})");
    ASSERT_SUBSTR(prompt, "Extract the person");
    ASSERT_SUBSTR(prompt, "Previous invalid answer: {\"name\":1}");
    ASSERT_SUBSTR(prompt, "Reply again with ONLY JSON");
    return 0;
}

}  // namespace

int main() {
    struct Case {
        const char* name;
        int (*fn)();
    } cases[] = {
        {"object_schema_compiles", test_object_schema_compiles},
        {"invalid_json_fails", test_invalid_json_fails},
        {"max_items_nested_optional_tails", test_max_items_nested_optional_tails},
        {"repair_prompt_is_deterministic", test_repair_prompt_is_deterministic},
    };

    int failed = 0;
    const int count = static_cast<int>(sizeof(cases) / sizeof(cases[0]));
    for (const auto& test_case : cases) {
        std::printf("[json_schema_to_gbnf] %s ... ", test_case.name);
        std::fflush(stdout);
        const int rc = test_case.fn();
        if (rc == 0) {
            std::printf("OK\n");
        } else {
            std::printf("FAIL\n");
            ++failed;
        }
    }
    std::printf("\n[json_schema_to_gbnf] %d/%d passed\n", count - failed, count);
    return failed == 0 ? 0 : 1;
}
