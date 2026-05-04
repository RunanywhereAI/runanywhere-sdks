/**
 * @file test_tool_calling.cpp
 * @brief Behavioral tests for the rac_tool_call_* C ABI.
 *
 * Phase G-1 close-out. Covers the cross-SDK surface that Swift, Kotlin,
 * Flutter, Web, and React Native all rely on as a single source of truth:
 *
 *   1. Parse (default <tool_call>JSON</tool_call> format)
 *   2. Parse (LFM2 <|tool_call_start|>[func(arg)]<|tool_call_end|> format)
 *   3. Parse free-form (no tool call) -> parsed=false, clean_text = input
 *   4. format_prompt — default + LFM2
 *   5. build_initial_prompt end-to-end
 *   6. build_followup_prompt end-to-end (keep_tools_available true + false)
 *   7. normalize_json (unquoted keys)
 *   8. Free functions: repeated allocate/free round-trips with no crashes
 *   9. format_from_name + detect_format
 */

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_tool_calling.h"

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

// ---------------------------------------------------------------------------
// 1. parse: default <tool_call>JSON</tool_call>
// ---------------------------------------------------------------------------
int test_parse_default_structured() {
    const char* input =
        "let me help <tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\"}}</tool_call>";
    rac_tool_call_t result;
    rac_result_t rc = rac_tool_call_parse(input, &result);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(result.tool_name, "get_weather");
    ASSERT_SUBSTR(result.arguments_json, "\"location\"");
    ASSERT_SUBSTR(result.arguments_json, "\"Tokyo\"");
    ASSERT_EQ_INT(result.format, RAC_TOOL_FORMAT_DEFAULT);
    rac_tool_call_free(&result);
    return 0;
}

// ---------------------------------------------------------------------------
// 2. parse: LFM2 Pythonic format
// ---------------------------------------------------------------------------
int test_parse_lfm2_structured() {
    const char* input =
        "sure <|tool_call_start|>[get_weather(location=\"San Francisco\")]<|tool_call_end|>";
    rac_tool_call_t result;
    rac_result_t rc = rac_tool_call_parse(input, &result);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(result.tool_name, "get_weather");
    ASSERT_SUBSTR(result.arguments_json, "\"location\"");
    ASSERT_SUBSTR(result.arguments_json, "San Francisco");
    ASSERT_EQ_INT(result.format, RAC_TOOL_FORMAT_LFM2);
    rac_tool_call_free(&result);
    return 0;
}

// ---------------------------------------------------------------------------
// 3. parse: free-form text -> parsed=false, no tool_name, clean_text = input
// ---------------------------------------------------------------------------
int test_parse_free_form_returns_false() {
    const char* input = "Just a plain conversational answer, nothing to invoke.";
    rac_tool_call_t result;
    rac_result_t rc = rac_tool_call_parse(input, &result);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result.has_tool_call, RAC_FALSE);
    ASSERT_TRUE(result.tool_name == nullptr);
    ASSERT_TRUE(result.clean_text != nullptr);
    ASSERT_EQ_STR(result.clean_text, input);
    rac_tool_call_free(&result);
    return 0;
}

// ---------------------------------------------------------------------------
// 4a. format_prompt with 2 tools (default format)
// ---------------------------------------------------------------------------
int test_format_prompt_default_two_tools() {
    rac_tool_parameter_t loc_param = {"location", RAC_TOOL_PARAM_STRING,
                                      "City name", RAC_TRUE, nullptr};
    rac_tool_parameter_t expr_param = {"expression", RAC_TOOL_PARAM_STRING,
                                       "Math expression", RAC_TRUE, nullptr};
    rac_tool_definition_t tools[2] = {
        {"get_weather", "Get weather for a city", &loc_param, 1, nullptr},
        {"calculate", "Evaluate a math expression", &expr_param, 1, nullptr},
    };

    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_format_prompt(tools, 2, &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, "get_weather");
    ASSERT_SUBSTR(prompt, "calculate");
    ASSERT_SUBSTR(prompt, "<tool_call>");
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 4b. format_prompt JSON with format name = "lfm2"
// ---------------------------------------------------------------------------
int test_format_prompt_json_lfm2() {
    const char* tools_json =
        "[{\"name\":\"get_weather\",\"description\":\"Weather\",\"parameters\":[]},"
        "{\"name\":\"calculate\",\"description\":\"Math\",\"parameters\":[]}]";
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_format_prompt_json_with_format_name(tools_json, "lfm2", &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, "<|tool_call_start|>");
    ASSERT_SUBSTR(prompt, "<|tool_call_end|>");
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 5. build_initial_prompt end-to-end
// ---------------------------------------------------------------------------
int test_build_initial_prompt_end_to_end() {
    const char* tools_json =
        "[{\"name\":\"get_weather\",\"description\":\"Weather\",\"parameters\":[]}]";
    rac_tool_calling_options_t options = RAC_TOOL_CALLING_OPTIONS_DEFAULT;
    options.format = RAC_TOOL_FORMAT_DEFAULT;

    char* prompt = nullptr;
    rac_result_t rc =
        rac_tool_call_build_initial_prompt("what is the weather in Tokyo?", tools_json,
                                           &options, &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, "get_weather");
    ASSERT_SUBSTR(prompt, "what is the weather in Tokyo?");
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 6a. build_followup_prompt — keep_tools_available = false
// ---------------------------------------------------------------------------
int test_build_followup_prompt_no_tools() {
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_followup_prompt(
        "what is the weather in Tokyo?",
        /*tools_prompt*/ nullptr,
        "get_weather",
        "{\"temperature_c\":22,\"condition\":\"sunny\"}",
        /*keep_tools_available*/ RAC_FALSE,
        &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, "get_weather");
    ASSERT_SUBSTR(prompt, "temperature_c");
    ASSERT_SUBSTR(prompt, "what is the weather in Tokyo?");
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 6b. build_followup_prompt — keep_tools_available = true (tools_prompt echoed)
// ---------------------------------------------------------------------------
int test_build_followup_prompt_keep_tools() {
    const char* tools_prompt = "PRE-RENDERED TOOLS PROMPT BLOCK";
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_followup_prompt(
        "compute 5*10", tools_prompt, "calculate", "{\"result\":50}",
        /*keep_tools_available*/ RAC_TRUE, &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, tools_prompt);
    ASSERT_SUBSTR(prompt, "calculate");
    ASSERT_SUBSTR(prompt, "\"result\":50");
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 7. normalize_json: unquoted keys become quoted
// ---------------------------------------------------------------------------
int test_normalize_json_unquoted_keys() {
    const char* input = "{tool: \"get_weather\", arguments: {location: \"Tokyo\"}}";
    char* out = nullptr;
    rac_result_t rc = rac_tool_call_normalize_json(input, &out);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(out != nullptr);
    ASSERT_SUBSTR(out, "\"tool\"");
    ASSERT_SUBSTR(out, "\"arguments\"");
    ASSERT_SUBSTR(out, "\"location\"");
    rac_free(out);
    return 0;
}

// ---------------------------------------------------------------------------
// 8. Free functions: repeated allocate/free never leaks into caller
//    (exercises the matching allocator + idempotent free)
// ---------------------------------------------------------------------------
int test_free_functions_idempotent() {
    for (int i = 0; i < 100; ++i) {
        rac_tool_call_t result;
        rac_result_t rc = rac_tool_call_parse(
            "<tool_call>{\"tool\":\"t\",\"arguments\":{\"k\":\"v\"}}</tool_call>", &result);
        ASSERT_EQ_INT(rc, RAC_SUCCESS);
        rac_tool_call_free(&result);
        // Double-free check: second call must be a no-op now that pointers are NULL.
        rac_tool_call_free(&result);
    }
    // Null-pointer safety
    rac_tool_call_free(nullptr);
    return 0;
}

// ---------------------------------------------------------------------------
// 9. format_from_name + detect_format
// ---------------------------------------------------------------------------
int test_format_name_round_trip() {
    ASSERT_EQ_INT(rac_tool_call_format_from_name("default"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("DEFAULT"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("lfm2"), RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("LFM2"), RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("unknown"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name(nullptr), RAC_TOOL_FORMAT_DEFAULT);

    ASSERT_EQ_INT(rac_tool_call_detect_format("text <tool_call>{}</tool_call>"),
                  RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_detect_format("<|tool_call_start|>[f()]<|tool_call_end|>"),
                  RAC_TOOL_FORMAT_LFM2);
    return 0;
}

// ---------------------------------------------------------------------------
// 10. parse -> tool result JSON -> follow-up prompt loop
// ---------------------------------------------------------------------------
int test_tool_result_loop() {
    const char* input =
        "checking <tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\"}}</tool_call>";
    rac_tool_call_t parsed;
    rac_result_t rc = rac_tool_call_parse(input, &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(parsed.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(parsed.tool_name, "get_weather");
    ASSERT_SUBSTR(parsed.arguments_json, "\"Tokyo\"");

    char* result_json = nullptr;
    rc = rac_tool_call_result_to_json(parsed.tool_name, RAC_TRUE,
                                      "{\"temperature_c\":22,\"condition\":\"clear\"}",
                                      nullptr, &result_json);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(result_json != nullptr);
    ASSERT_SUBSTR(result_json, "\"toolName\":\"get_weather\"");
    ASSERT_SUBSTR(result_json, "\"success\":true");
    ASSERT_SUBSTR(result_json, "\"temperature_c\":22");

    char* followup = nullptr;
    rc = rac_tool_call_build_followup_prompt("what is the weather in Tokyo?", nullptr,
                                             parsed.tool_name, result_json, RAC_FALSE,
                                             &followup);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(followup != nullptr);
    ASSERT_SUBSTR(followup, "what is the weather in Tokyo?");
    ASSERT_SUBSTR(followup, "get_weather");
    ASSERT_SUBSTR(followup, "\"condition\":\"clear\"");

    rac_free(followup);
    rac_free(result_json);
    rac_tool_call_free(&parsed);
    return 0;
}

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;

    TestCase cases[] = {
        {"parse_default_structured",    test_parse_default_structured},
        {"parse_lfm2_structured",       test_parse_lfm2_structured},
        {"parse_free_form_returns_false", test_parse_free_form_returns_false},
        {"format_prompt_default_two_tools", test_format_prompt_default_two_tools},
        {"format_prompt_json_lfm2",     test_format_prompt_json_lfm2},
        {"build_initial_prompt_e2e",    test_build_initial_prompt_end_to_end},
        {"build_followup_prompt_no_tools", test_build_followup_prompt_no_tools},
        {"build_followup_prompt_keep_tools", test_build_followup_prompt_keep_tools},
        {"normalize_json_unquoted_keys", test_normalize_json_unquoted_keys},
        {"free_functions_idempotent",   test_free_functions_idempotent},
        {"format_name_round_trip",      test_format_name_round_trip},
        {"tool_result_loop",            test_tool_result_loop},
    };

    int num_cases = static_cast<int>(sizeof(cases) / sizeof(cases[0]));
    int failed = 0;
    for (int i = 0; i < num_cases; ++i) {
        std::printf("[tool_calling] %s ... ", cases[i].name);
        std::fflush(stdout);
        int rc = cases[i].fn();
        if (rc == 0) {
            std::printf("OK\n");
        } else {
            std::printf("FAIL\n");
            ++failed;
        }
    }
    std::printf("\n[tool_calling] %d/%d passed\n", num_cases - failed, num_cases);
    return failed == 0 ? 0 : 1;
}
