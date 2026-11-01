/**
 * @file test_tool_calling.cpp
 * @brief Behavioral tests for the private tool parser primitives.
 *
 * The public SDK contract is generated protobuf. These tests exercise the
 * parser implementation used behind that contract:
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
#include <nlohmann/json.hpp>
#include <string>

#include "features/llm/tool_calling_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_tool_calling.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"

#include "features/llm/tool_calling_result_internal.h"
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

#define ASSERT_EQ_STR(actual, expected)                                                           \
    do {                                                                                          \
        if (std::strcmp((actual), (expected)) != 0) {                                             \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d\n  expected: \"%s\"\n  actual:   \"%s\"\n", \
                         __FILE__, __LINE__, (expected), (actual));                               \
            return 1;                                                                             \
        }                                                                                         \
    } while (0)

#define ASSERT_SUBSTR(haystack, needle)                                                         \
    do {                                                                                        \
        if (std::strstr((haystack), (needle)) == nullptr) {                                     \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: '%s' not found in '%.200s'\n", __FILE__, \
                         __LINE__, (needle), (haystack));                                       \
            return 1;                                                                           \
        }                                                                                       \
    } while (0)

// ---------------------------------------------------------------------------
// 1. parse: default <tool_call>JSON</tool_call>
// ---------------------------------------------------------------------------
int test_parse_default_structured() {
    const char* input =
        "let me help "
        "<tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\"}}</tool_call>";
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
// 1b. parse: an argument that shares a name with a tool-name key
//     ("name", "tool", "input", ...) must not be taken for the call's own key.
//     The JSON is re-serialized with sorted keys before extraction, so
//     "arguments" always precedes "name" / "tool".
// ---------------------------------------------------------------------------
int test_parse_default_nested_keys_stay_arguments() {
    struct Case {
        const char* input;
        const char* tool_name;
        const char* arguments_json;
    };
    const Case cases[] = {
        // Hermes / Qwen native shape, tool with a `name` parameter
        {R"(<tool_call>{"name":"create_contact","arguments":{"name":"Alice"}}</tool_call>)",
         "create_contact", R"({"name":"Alice"})"},
        // the shape the default prompt asks for, tool with a `tool` parameter
        {R"(<tool_call>{"tool":"run_command","arguments":{"tool":"git"}}</tool_call>)",
         "run_command", R"({"tool":"git"})"},
        // flat arguments: a nested `input` is not the argument wrapper
        {R"(<tool_call>{"tool":"translate","text":"hi","options":{"input":"en"}}</tool_call>)",
         "translate", R"({"options":{"input":"en"},"text":"hi"})"},
        // OpenAI-style envelope resolves one level down
        {R"(<tool_call>{"type":"function",)"
         R"("function":{"name":"get_weather","arguments":{"city":"Paris"}}}</tool_call>)",
         "get_weather", R"({"city":"Paris"})"},
        // ...including its JSON-encoded string arguments
        {R"(<tool_call>{"type":"function",)"
         R"("function":{"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}}</tool_call>)",
         "get_weather", R"({"city":"Paris"})"},
        // OpenAI's tool_calls array with a single call
        {R"(<tool_call>{"tool_calls":[{"function":)"
         R"({"name":"get_weather","arguments":{"city":"Paris"}}}]}</tool_call>)",
         "get_weather", R"({"city":"Paris"})"},
        // ...as the API sends it, with id, type and string arguments
        {R"(<tool_call>{"tool_calls":[{"id":"call_1","type":"function","function":)"
         R"({"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}}]}</tool_call>)",
         "get_weather", R"({"city":"Paris"})"},
        // a tool_calls array with no call in it keeps the old reading
        {R"(<tool_call>{"tool_calls":[]}</tool_call>)", "tool_calls", R"({"input":"[]"})"},
        {R"(<tool_call>{"tool_calls":[{"city":"Paris"}]}</tool_call>)", "tool_calls",
         R"({"input":"[{\"city\":\"Paris\"}]"})"},
        // two calls are not collapsed into the first one
        {R"(<tool_call>{"tool_calls":[{"name":"a"},{"name":"b"}]}</tool_call>)", "tool_calls",
         R"({"input":"[{\"name\":\"a\"},{\"name\":\"b\"}]"})"},
        // an array argument of a name-as-key tool is not read as a call
        {R"(<tool_call>{"search":[{"name":"Alice"}]}</tool_call>)", "search",
         R"({"input":"[{\"name\":\"Alice\"}]"})"},
        // a string alias names the call; an object under another alias is an argument
        {R"(<tool_call>{"name":"open_ticket","tool":{"function":"inner"}}</tool_call>)",
         "open_ticket", R"({"tool":{"function":"inner"}})"},
        // outside the envelope a string argument is still wrapped, not decoded
        {R"(<tool_call>{"tool":"echo","arguments":"{\"a\":1}"}</tool_call>)", "echo",
         R"({"input":"{\"a\":1}"})"},
    };
    for (const Case& c : cases) {
        rac_tool_call_t result;
        rac_result_t rc = rac_tool_call_parse(c.input, &result);
        ASSERT_EQ_INT(rc, RAC_SUCCESS);
        ASSERT_EQ_INT(result.has_tool_call, RAC_TRUE);
        ASSERT_EQ_STR(result.tool_name, c.tool_name);
        ASSERT_EQ_STR(result.arguments_json, c.arguments_json);
        rac_tool_call_free(&result);
    }
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

int test_parse_lfm2_invalid_utf8() {
    const char* input =
        "<|tool_call_start|>[get_weather(location='\xC3\x28')]<|tool_call_end|>";
    rac_tool_call_t result{};
    const rac_result_t rc = rac_tool_call_parse(input, &result);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result.has_tool_call, RAC_TRUE);
    ASSERT_TRUE(result.tool_name != nullptr);
    ASSERT_EQ_STR(result.tool_name, "get_weather");
    ASSERT_TRUE(result.arguments_json != nullptr);
    ASSERT_EQ_STR(result.arguments_json, "{\"location\":\"\xEF\xBF\xBD(\"}");
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
    rac_tool_parameter_t loc_param = {"location", RAC_TOOL_PARAM_STRING, "City name", RAC_TRUE,
                                      nullptr};
    rac_tool_parameter_t expr_param = {"expression", RAC_TOOL_PARAM_STRING, "Math expression",
                                       RAC_TRUE, nullptr};
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
    rac_result_t rc =
        rac_tool_call_format_prompt_json_with_format_name(tools_json, "lfm2", &prompt);
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
    const char* tools_json = R"([{"name":"get_weather","description":"Weather","parameters":[]}])";
    rac_tool_calling_options_t options = RAC_TOOL_CALLING_OPTIONS_DEFAULT;
    options.format = RAC_TOOL_FORMAT_DEFAULT;

    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_initial_prompt("what is the weather in Tokyo?",
                                                         tools_json, &options, &prompt);
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
        /*tools_prompt*/ nullptr, "get_weather", R"({"temperature_c":22,"condition":"sunny"})",
        /*keep_tools_available*/ RAC_FALSE, &prompt);
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
// 6c. search_web follow-up stays current, grounded, compact, and attributed
// ---------------------------------------------------------------------------
int test_build_search_web_followup_prompt() {
    const char* evidence = R"({
      "query":"current Google Play target API requirement",
      "source_url":"https://developer.android.com/google/play/requirements/target-sdk",
      "summary":"From August 31, 2024, existing mobile apps need API 34 for availability.",
      "heading":"Target API level requirements",
      "related_results":[
        {"title":"2025 mobile requirement","text":"From August 31, 2025, new mobile apps and updates must target API 35.","url":"https://developer.android.com/google/play/requirements/target-sdk#mobile-2025"},
        {"title":"2026 announced requirement","text":"From August 31, 2026, new mobile apps and updates must target API 36.","url":"https://developer.android.com/google/play/requirements/target-sdk#mobile-2026"},
        {"title":"discarded noisy result","text":"This third related result must not crowd the small-model context.","url":"https://example.com/discard-me"}
      ]
    })";

    char* prompt = nullptr;
    const rac_result_t rc = rac_tool_call_build_followup_prompt(
        "Find the current Google Play target API requirement for a new mobile app and include a "
        "source URL.",
        /*tools_prompt=*/nullptr, "search_web", evidence,
        /*keep_tools_available=*/RAC_FALSE, &prompt);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prompt != nullptr);
    ASSERT_SUBSTR(prompt, "Current UTC date:");
    ASSERT_SUBSTR(prompt, "policy effective on the current date");
    ASSERT_SUBSTR(prompt, "past transitions, future announcements");
    ASSERT_SUBSTR(prompt, "not from model memory");
    ASSERT_SUBSTR(prompt, "`Source: <URL>` using source_url verbatim");
    ASSERT_SUBSTR(prompt, "API 34");
    ASSERT_SUBSTR(prompt, "API 35");
    ASSERT_SUBSTR(prompt, "API 36");
    ASSERT_SUBSTR(prompt, "https://developer.android.com/google/play/requirements/target-sdk");
    ASSERT_TRUE(std::strstr(prompt, "discarded noisy result") == nullptr);
    ASSERT_TRUE(std::strlen(prompt) < 2600);
    rac_free(prompt);
    return 0;
}

// ---------------------------------------------------------------------------
// 7. normalize_json: unquoted keys become quoted
// ---------------------------------------------------------------------------
int test_normalize_json_unquoted_keys() {
    const char* input = R"({tool: "get_weather", arguments: {location: "Tokyo"}})";
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
            R"(<tool_call>{"tool":"t","arguments":{"k":"v"}}</tool_call>)", &result);
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

// RUN-83: lock the per-model-family tool-call FORMAT flavor. The LFM / Liquid
// family emits the Python-style [name(args)] LFM2 tags; every other shipping
// family — Qwen3 / Qwen3.5 / Qwen3-VL (the v81 1.7B/4B/8B/27B set) and the
// 1-bit/ternary Bonsai models (same ChatML block) — uses the DEFAULT
// <tool_call>{json}</tool_call> flavor. On QHexRT the tool-call GRAMMAR
// (toolcall_opt:<names>, see the run-loop tests) is family-independent, so the
// flavor only steers the text parser for non-grammar engines (llama.cpp/onnx).
int test_tool_call_format_per_family() {
    // LFM2.5 (350M / 230M): every catalogued alias resolves to LFM2.
    ASSERT_EQ_INT(rac_tool_call_format_from_name("lfm"), RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("lfm2"), RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("liquid"), RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("Liquid"), RAC_TOOL_FORMAT_LFM2);

    // Qwen family (v81 1.7B/4B/8B/27B) + 1-bit/ternary Bonsai → DEFAULT.
    ASSERT_EQ_INT(rac_tool_call_format_from_name("qwen"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("qwen3"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("bonsai"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_format_from_name(""), RAC_TOOL_FORMAT_DEFAULT);

    // Round-trip: a model emitting a given flavor is detected as that flavor.
    ASSERT_EQ_INT(rac_tool_call_detect_format("<|tool_call_start|>[get_time()]<|tool_call_end|>"),
                  RAC_TOOL_FORMAT_LFM2);
    ASSERT_EQ_INT(
        rac_tool_call_detect_format("<tool_call>{\"tool\":\"get_time\",\"arguments\":{}}</tool_call>"),
        RAC_TOOL_FORMAT_DEFAULT);
    return 0;
}

// RUN-80 (grammar-engage): the bare Pythonic `[name(args)]` format the QHexRT grammar
// emits — detection is strict (no false positives on prose/markdown), parsing reuses the
// shared Pythonic parser, and the tagged formats still take precedence.
int test_pythonic_detect_and_parse() {
    ASSERT_EQ_INT(rac_tool_call_format_from_name("pythonic"), RAC_TOOL_FORMAT_PYTHONIC);
    ASSERT_EQ_INT(rac_tool_call_format_from_name("grammar"), RAC_TOOL_FORMAT_PYTHONIC);

    // Bare calls detected as PYTHONIC (leading whitespace tolerated; no-arg allowed).
    ASSERT_EQ_INT(rac_tool_call_detect_format("[get_weather(location=\"Tokyo\")]"),
                  RAC_TOOL_FORMAT_PYTHONIC);
    ASSERT_EQ_INT(rac_tool_call_detect_format("  [calculate(expression=\"45 * 12\")]"),
                  RAC_TOOL_FORMAT_PYTHONIC);
    ASSERT_EQ_INT(rac_tool_call_detect_format("[get_time()]"), RAC_TOOL_FORMAT_PYTHONIC);

    // Strict predicate: prose, citations, plain lists and markdown links are NOT calls.
    ASSERT_EQ_INT(rac_tool_call_detect_format("The capital of France is Paris."),
                  RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_detect_format("See [1] and [2] for details."),
                  RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_detect_format("[a list, of, things]"), RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_detect_format("[link](https://example.com)"),
                  RAC_TOOL_FORMAT_DEFAULT);
    const char* invalid_arguments[] = {
        "[inspect(=2)]",          "[inspect(  =2)]",
        "[inspect(1x=2)]",        "[inspect(x-y=2)]",
        "[inspect(x,good=2)]",    "[inspect(x)extra=2)]",
        "[inspect(\xFF,good=2)]", "[inspect(\xFF)=2)]",
        "[inspect(\xFF]=2)]",     "[inspect(\xFF(other=2))]",
    };
    for (const char* input : invalid_arguments) {
        ASSERT_EQ_INT(rac_tool_call_detect_format(input), RAC_TOOL_FORMAT_DEFAULT);
    }
    // Tagged formats win (bare check runs last).
    ASSERT_EQ_INT(rac_tool_call_detect_format("<tool_call>{}</tool_call>"),
                  RAC_TOOL_FORMAT_DEFAULT);
    ASSERT_EQ_INT(rac_tool_call_detect_format("<|tool_call_start|>[f()]<|tool_call_end|>"),
                  RAC_TOOL_FORMAT_LFM2);

    // Auto-detect parse of a bare call yields the tool + typed args.
    rac_tool_call_t call;
    rac_result_t rc = rac_tool_call_parse("[get_weather(location=\"Tokyo\")]", &call);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(call.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(call.tool_name, "get_weather");
    ASSERT_SUBSTR(call.arguments_json, "\"location\"");
    ASSERT_SUBSTR(call.arguments_json, "Tokyo");
    ASSERT_EQ_INT(call.format, RAC_TOOL_FORMAT_PYTHONIC);
    rac_tool_call_free(&call);

    // No-arg bare call.
    rac_tool_call_t call2;
    rc = rac_tool_call_parse("[get_time()]", &call2);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(call2.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(call2.tool_name, "get_time");
    rac_tool_call_free(&call2);

    // A markdown link is not misparsed into a tool call (graceful no-call).
    rac_tool_call_t call3;
    rc = rac_tool_call_parse("[link](https://example.com)", &call3);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(call3.has_tool_call, RAC_FALSE);
    rac_tool_call_free(&call3);
    return 0;
}

struct Utf8ArgumentCase {
    const char* value;
    const char* expected;
    rac_tool_param_type_t type;
};

// Check decoded values and schema validation, not just the presence of U+FFFD:
// repairing only at dump time can leave extra quotes or turn objects into strings.
int check_pythonic_utf8_arguments(const Utf8ArgumentCase* cases, size_t count) {
    for (const auto format : {RAC_TOOL_FORMAT_LFM2, RAC_TOOL_FORMAT_PYTHONIC}) {
        for (size_t i = 0; i < count; ++i) {
            const auto& c = cases[i];
            std::string input = "[inspect(value=";
            input += c.value;
            input += ")]";
            if (format == RAC_TOOL_FORMAT_LFM2) {
                input = "<|tool_call_start|>" + input + "<|tool_call_end|>";
            }
            rac_tool_call_t call{};
            const rac_result_t rc = rac_tool_call_parse(input.c_str(), &call);
            ASSERT_EQ_INT(rc, RAC_SUCCESS);
            ASSERT_EQ_INT(call.has_tool_call, RAC_TRUE);
            ASSERT_EQ_INT(call.format, format);
            ASSERT_TRUE(call.tool_name != nullptr);
            ASSERT_EQ_STR(call.tool_name, "inspect");
            ASSERT_TRUE(call.arguments_json != nullptr);
            const auto args = nlohmann::json::parse(call.arguments_json, nullptr, false);
            ASSERT_TRUE(args.is_object());
            ASSERT_TRUE(args.contains("value"));
            ASSERT_TRUE(args["value"] == nlohmann::json::parse(c.expected));

            rac_tool_parameter_t param{"value", c.type, "Value to inspect", RAC_TRUE, nullptr};
            rac_tool_definition_t tool{"inspect", "Inspect a value", &param, 1, nullptr};
            rac_tool_call_validation_t validation{};
            ASSERT_EQ_INT(rac_tool_call_validate(&call, &tool, 1, &validation), RAC_SUCCESS);
            ASSERT_EQ_INT(validation.is_valid, RAC_TRUE);
            rac_tool_call_validation_free(&validation);
            rac_tool_call_free(&call);
        }
    }
    return 0;
}

int test_pythonic_utf8_strings() {
    const Utf8ArgumentCase cases[] = {
        {"'\xC3\x28'", "\"\xEF\xBF\xBD(\"", RAC_TOOL_PARAM_STRING},
        {"\"\xC3\x28\"", "\"\xEF\xBF\xBD(\"", RAC_TOOL_PARAM_STRING},
        {"\"quoted \\\"\xFF\\\"\\nline\"", "\"quoted \\\"\xEF\xBF\xBD\\\"\\nline\"",
         RAC_TOOL_PARAM_STRING},
        {"\"\xE2\x82\"", "\"\xEF\xBF\xBD\xEF\xBF\xBD\"", RAC_TOOL_PARAM_STRING},
        // Broken JSON stays a string even if duplicate keys were observed
        // before the syntax error. Valid ambiguous objects are tested below.
        {R"({"x":1,"x":2,})", R"("{\"x\":1,\"x\":2,}")", RAC_TOOL_PARAM_STRING},
        {R"([{"x":1,"x":2},])", R"("[{\"x\":1,\"x\":2},]")", RAC_TOOL_PARAM_STRING},
        {R"({"x":1,"x":2} trailing)", R"("{\"x\":1,\"x\":2} trailing")", RAC_TOOL_PARAM_STRING},
        {"{\"x\xFF\":1,\"x\xFE\":2,}", "\"{\\\"x\xEF\xBF\xBD\\\":1,\\\"x\xEF\xBF\xBD\\\":2,}\"",
         RAC_TOOL_PARAM_STRING},
    };
    return check_pythonic_utf8_arguments(cases, sizeof(cases) / sizeof(cases[0]));
}

int test_pythonic_utf8_nested_values() {
    const Utf8ArgumentCase cases[] = {
        {"{\"q\":\"\xFF\",\"count\":2,\"enabled\":true}",
         "{\"q\":\"\xEF\xBF\xBD\",\"count\":2,\"enabled\":true}", RAC_TOOL_PARAM_OBJECT},
        {"[1,{\"q\":\"\xC3\x28\"},false,null]", "[1,{\"q\":\"\xEF\xBF\xBD(\"},false,null]",
         RAC_TOOL_PARAM_ARRAY},
        {"{\"\xFF\":[\"\xFF\"]}", "{\"\xEF\xBF\xBD\":[\"\xEF\xBF\xBD\"]}", RAC_TOOL_PARAM_OBJECT},
        {R"({"x":{"x":1},"y":{"x":2}})", R"({"x":{"x":1},"y":{"x":2}})", RAC_TOOL_PARAM_OBJECT},
        {R"([{"x":1},{"x":2}])", R"([{"x":1},{"x":2}])", RAC_TOOL_PARAM_ARRAY},
        {"{\"x\xFF\":1,\"x\xC3\x28\":2}", "{\"x\xEF\xBF\xBD\":1,\"x\xEF\xBF\xBD(\":2}",
         RAC_TOOL_PARAM_OBJECT},
    };
    ASSERT_EQ_INT(check_pythonic_utf8_arguments(cases, sizeof(cases) / sizeof(cases[0])), 0);

    // Repaired or escaped names may collide at any object depth, including
    // inside arrays. Reject the entire call rather than returning a partial
    // object or accepting the ambiguous value as a raw string.
    const char* collisions[] = {
        "{\"x\xFF\":1,\"x\xFE\":2}",
        "{\"outer\":{\"x\xFF\":1,\"x\xEF\xBF\xBD\":2}}",
        "{\"outer\":{\"x\xEF\xBF\xBD\":1,\"x\xFF\":2}}",
        "[{\"x\":0},{\"outer\":[{\"x\xFF\":1,\"x\xFE\":2}]}]",
        "{\"left\":{\"q\":0},\"right\":{\"x\xFF\":1,\"x\xFE\":2}}",
        "{\"x\xFF\":1,\"x\\uFFFD\":2}",
        R"({"x":1,"\u0078":2})",
        R"({"outer":{"x":1,"x":2}})",
        "{\"x\xFF\":{\"a\":1},\"x\xFE\":{\"b\":2}}",
    };
    for (const auto format : {RAC_TOOL_FORMAT_LFM2, RAC_TOOL_FORMAT_PYTHONIC}) {
        for (const char* collision : collisions) {
            std::string input = std::string("[inspect(value=") + collision + ")]";
            if (format == RAC_TOOL_FORMAT_LFM2) {
                input = "<|tool_call_start|>" + input + "<|tool_call_end|>";
            }
            rac_tool_call_t call{};
            ASSERT_EQ_INT(rac_tool_call_parse(input.c_str(), &call), RAC_SUCCESS);
            ASSERT_EQ_INT(call.has_tool_call, RAC_FALSE);
            ASSERT_TRUE(call.tool_name == nullptr);
            ASSERT_TRUE(call.arguments_json == nullptr);
            ASSERT_TRUE(call.clean_text != nullptr);
            ASSERT_EQ_STR(call.clean_text, input.c_str());
            rac_tool_call_free(&call);
        }
    }
    return 0;
}

int test_pythonic_utf8_invalid_scalars() {
    const Utf8ArgumentCase cases[] = {
        {"\"\x80\"", "\"\xEF\xBF\xBD\"", RAC_TOOL_PARAM_STRING},
        {"\"\xC0\xAF\"", "\"\xEF\xBF\xBD\xEF\xBF\xBD\"", RAC_TOOL_PARAM_STRING},
        {"\"\xE0\x80\x80\"", "\"\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\"", RAC_TOOL_PARAM_STRING},
        {"\"\xED\xA0\x80\"", "\"\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\"", RAC_TOOL_PARAM_STRING},
        {"\"\xF4\x90\x80\x80\"", "\"\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\"",
         RAC_TOOL_PARAM_STRING},
    };
    return check_pythonic_utf8_arguments(cases, sizeof(cases) / sizeof(cases[0]));
}

int test_pythonic_utf8_valid_unicode() {
    const char* value =
        "\"ASCII \xC2\x80\xDF\xBF\xE0\xA0\x80\xED\x9F\xBF\xEE\x80\x80\xEF\xBF\xBF"
        "\xF0\x90\x80\x80\xF4\x8F\xBF\xBF \xE6\x9D\xB1\xE4\xBA\xAC \xF0\x9F\x98\x80\"";
    const Utf8ArgumentCase cases[] = {{value, value, RAC_TOOL_PARAM_STRING}};
    return check_pythonic_utf8_arguments(cases, 1);
}

int test_pythonic_utf8_argument_key() {
    struct KeyCase {
        const char* arguments;
        const char* expected;
    };
    const KeyCase cases[] = {
        {"value=1,bad_\xFF=2", "{\"value\":1,\"bad_\xEF\xBF\xBD\":2}"},
        {"bad_\xFF=2", "{\"bad_\xEF\xBF\xBD\":2}"},
        {"\xFF=2", "{\"\xEF\xBF\xBD\":2}"},
        {"bad_\xC3 =2", "{\"bad_\xEF\xBF\xBD\":2}"},
        {"\xE6\x9D\xB1\xE4\xBA\xAC=2", "{\"\xE6\x9D\xB1\xE4\xBA\xAC\":2}"},
    };
    for (const auto format : {RAC_TOOL_FORMAT_LFM2, RAC_TOOL_FORMAT_PYTHONIC}) {
        for (const auto& c : cases) {
            std::string input = std::string("[inspect(") + c.arguments + ")]";
            if (format == RAC_TOOL_FORMAT_LFM2) {
                input = "<|tool_call_start|>" + input + "<|tool_call_end|>";
            }
            ASSERT_EQ_INT(rac_tool_call_detect_format(input.c_str()), format);
            rac_tool_call_t call{};
            ASSERT_EQ_INT(rac_tool_call_parse(input.c_str(), &call), RAC_SUCCESS);
            ASSERT_EQ_INT(call.has_tool_call, RAC_TRUE);
            ASSERT_EQ_INT(call.format, format);
            ASSERT_TRUE(call.tool_name != nullptr);
            ASSERT_EQ_STR(call.tool_name, "inspect");
            ASSERT_TRUE(call.arguments_json != nullptr);
            const auto args = nlohmann::json::parse(call.arguments_json, nullptr, false);
            ASSERT_TRUE(args.is_object());
            ASSERT_TRUE(args == nlohmann::json::parse(c.expected));
            rac_tool_call_free(&call);
        }

        // Different raw keys can become identical after UTF-8 repair. Reject
        // the whole call rather than silently dropping one argument.
        const char* collisions[] = {
            "[inspect(x\xFF=1,x\xFE=2)]",         "[inspect(x\xFF=1,x\xEF\xBF\xBD=2)]",
            "[inspect(x\xEF\xBF\xBD=1,x\xFF=2)]", "[inspect(x\xFF=1,x\xFF=2)]",
            "[inspect(value=1,value=2)]",
        };
        for (const char* collision : collisions) {
            std::string rejected_input = collision;
            if (format == RAC_TOOL_FORMAT_LFM2) {
                rejected_input = "<|tool_call_start|>" + rejected_input + "<|tool_call_end|>";
            }
            ASSERT_EQ_INT(rac_tool_call_detect_format(rejected_input.c_str()), format);
            for (const bool explicit_format : {false, true}) {
                rac_tool_call_t rejected{};
                const rac_result_t rc =
                    explicit_format
                        ? rac_tool_call_parse_with_format(rejected_input.c_str(), format, &rejected)
                        : rac_tool_call_parse(rejected_input.c_str(), &rejected);
                ASSERT_EQ_INT(rc, RAC_SUCCESS);
                ASSERT_EQ_INT(rejected.has_tool_call, RAC_FALSE);
                ASSERT_TRUE(rejected.tool_name == nullptr);
                ASSERT_TRUE(rejected.arguments_json == nullptr);
                ASSERT_TRUE(rejected.clean_text != nullptr);
                ASSERT_EQ_STR(rejected.clean_text, rejected_input.c_str());
                rac_tool_call_free(&rejected);
            }
        }
    }
    return 0;
}

// An unknown model-generated name must produce a validation failure, even if
// its bytes are malformed; it must never throw while serializing the error.
int test_validate_invalid_utf8_tool_name() {
    const struct {
        const char* name;
        const char* repaired_name;
    } cases[] = {
        {"unknown_\xFF", "unknown_\xEF\xBF\xBD"},
        {"unknown_\xC3\x28", "unknown_\xEF\xBF\xBD("},
        {"unknown_ascii", "unknown_ascii"},
        {"unknown_\xE6\x9D\xB1\xE4\xBA\xAC_\xF0\x9F\x98\x80",
         "unknown_\xE6\x9D\xB1\xE4\xBA\xAC_\xF0\x9F\x98\x80"},
    };
    for (const auto& test_case : cases) {
        const std::string input = std::string("<tool_call>{\"tool\":\"") + test_case.name +
                                  "\",\"arguments\":{}}</tool_call>";
        const std::string expected_error = std::string("Unknown tool: ") + test_case.repaired_name;
        rac_tool_call_t call{};
        ASSERT_EQ_INT(rac_tool_call_parse(input.c_str(), &call), RAC_SUCCESS);
        ASSERT_EQ_INT(call.has_tool_call, RAC_TRUE);
        for (const bool json_definitions : {false, true}) {
            rac_tool_call_validation_t validation{};
            const rac_result_t rc = json_definitions
                                        ? rac_tool_call_validate_json(&call, "[]", &validation)
                                        : rac_tool_call_validate(&call, nullptr, 0, &validation);
            ASSERT_EQ_INT(rc, RAC_SUCCESS);
            ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
            ASSERT_EQ_INT(validation.error_code, RAC_ERROR_VALIDATION_FAILED);
            ASSERT_TRUE(validation.validation_errors_json != nullptr);
            const auto errors =
                nlohmann::json::parse(validation.validation_errors_json, nullptr, false);
            ASSERT_TRUE(errors.is_array());
            ASSERT_EQ_INT(errors.size(), 1);
            ASSERT_TRUE(errors[0] == expected_error);
            ASSERT_TRUE(validation.error_message != nullptr);
            ASSERT_EQ_STR(validation.error_message, expected_error.c_str());
            rac_tool_call_validation_free(&validation);
        }
        rac_tool_call_free(&call);
    }
    return 0;
}

#if defined(RAC_HAVE_PROTOBUF)
int test_tool_result_utf8_error_payload() {
    using rac::llm::tool_calling::tool_result_payload_json;
    runanywhere::v1::ToolResult result;
    ASSERT_EQ_STR(tool_result_payload_json(result).c_str(), "{}");
    // Construct the executor result directly: malformed proto string fields
    // cannot reliably round-trip through the strict protobuf byte parser.
    result.set_error("failed: \"\xC3\x28\"\n");
    auto payload = nlohmann::json::parse(tool_result_payload_json(result), nullptr, false);
    ASSERT_TRUE(payload.is_object());
    ASSERT_TRUE(payload["error"] == "failed: \"\xEF\xBF\xBD(\"\n");
    result.set_error("\xE6\x9D\xB1\xE4\xBA\xAC \xF0\x9F\x98\x80");
    payload = nlohmann::json::parse(tool_result_payload_json(result), nullptr, false);
    ASSERT_TRUE(payload.is_object());
    ASSERT_TRUE(payload["error"] == result.error());
    // A real result takes precedence over the error, preserving its raw JSON.
    result.set_result_json("{\"answer\":42}");
    ASSERT_EQ_STR(tool_result_payload_json(result).c_str(), "{\"answer\":42}");
    return 0;
}
#endif

int test_parse_pythonic_invalid_utf8() {
    const char* input = "[get_weather(location='\xC3\x28')]";
    rac_tool_call_t result{};
    const rac_result_t rc = rac_tool_call_parse(input, &result);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result.has_tool_call, RAC_TRUE);
    ASSERT_TRUE(result.tool_name != nullptr);
    ASSERT_EQ_STR(result.tool_name, "get_weather");
    ASSERT_TRUE(result.arguments_json != nullptr);
    ASSERT_EQ_STR(result.arguments_json, "{\"location\":\"\xEF\xBF\xBD(\"}");
    ASSERT_EQ_INT(result.format, RAC_TOOL_FORMAT_PYTHONIC);
    rac_tool_call_free(&result);
    return 0;
}

// RUN-80 (grammar-engage, review follow-up): the bare parser locates the call by the
// MATCHING ']' (quote- and nesting-aware), so trailing text, a later bracket group, or a
// ']' inside a string arg cannot corrupt the extraction; empty string args parse.
int test_pythonic_multibracket_and_special_args() {
    // A later bracket group + trailing text does not hijack the call; it becomes clean_text.
    rac_tool_call_t c1;
    rac_result_t rc = rac_tool_call_parse("[get_weather(location=\"Tokyo\")] see also [notes]", &c1);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(c1.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(c1.tool_name, "get_weather");
    ASSERT_SUBSTR(c1.arguments_json, "Tokyo");
    ASSERT_TRUE(c1.clean_text != nullptr);
    ASSERT_SUBSTR(c1.clean_text, "see also [notes]");
    rac_tool_call_free(&c1);

    // A ']' inside a quoted string arg does not close the call early.
    rac_tool_call_t c2;
    rc = rac_tool_call_parse("[note(text=\"a]b\")]", &c2);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(c2.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(c2.tool_name, "note");
    ASSERT_SUBSTR(c2.arguments_json, "a]b");
    rac_tool_call_free(&c2);

    // Empty string value parses (raw value "" is non-empty, so not rejected).
    rac_tool_call_t c3;
    rc = rac_tool_call_parse("[echo(msg=\"\")]", &c3);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(c3.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(c3.tool_name, "echo");
    ASSERT_SUBSTR(c3.arguments_json, "\"msg\"");
    rac_tool_call_free(&c3);

    // Trailing text after a no-arg call becomes clean_text.
    rac_tool_call_t c4;
    rc = rac_tool_call_parse("[get_time()] done", &c4);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(c4.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(c4.tool_name, "get_time");
    ASSERT_EQ_STR(c4.clean_text, "done");
    rac_tool_call_free(&c4);
    return 0;
}

// RUN-80 (grammar-engage): the bare-Pythonic prompt renders `[name(args)]` guidance with
// NO tags, so it matches what the grammar makes the model emit.
int test_pythonic_prompt_render() {
    char* out = nullptr;
    const char* tools = "[{\"name\":\"get_weather\",\"description\":\"w\",\"parameters\":[]}]";
    rac_result_t rc =
        rac_tool_call_format_prompt_json_with_format(tools, RAC_TOOL_FORMAT_PYTHONIC, &out);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(out != nullptr);
    ASSERT_SUBSTR(out, "[tool_name(");
    ASSERT_SUBSTR(out, "square brackets and NO other tags");
    ASSERT_TRUE(strstr(out, "<tool_call>") == nullptr);
    ASSERT_TRUE(strstr(out, "<|tool_call_start|>") == nullptr);
    free(out);
    return 0;
}

// ---------------------------------------------------------------------------
// 10. parse -> tool result JSON -> follow-up prompt loop
// ---------------------------------------------------------------------------
int test_tool_result_loop() {
    const char* input =
        "checking "
        "<tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\"}}</tool_call>";
    rac_tool_call_t parsed;
    rac_result_t rc = rac_tool_call_parse(input, &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(parsed.has_tool_call, RAC_TRUE);
    ASSERT_EQ_STR(parsed.tool_name, "get_weather");
    ASSERT_SUBSTR(parsed.arguments_json, "\"Tokyo\"");

    char* result_json = nullptr;
    rc = rac_tool_call_result_to_json(parsed.tool_name, RAC_TRUE,
                                      R"({"temperature_c":22,"condition":"clear"})", nullptr,
                                      &result_json);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(result_json != nullptr);
    ASSERT_SUBSTR(result_json, "\"toolName\":\"get_weather\"");
    ASSERT_SUBSTR(result_json, "\"success\":true");
    ASSERT_SUBSTR(result_json, "\"temperature_c\":22");

    char* followup = nullptr;
    rc = rac_tool_call_build_followup_prompt("what is the weather in Tokyo?", nullptr,
                                             parsed.tool_name, result_json, RAC_FALSE, &followup);
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

// ---------------------------------------------------------------------------
// 11. validate parsed call against local definitions
// ---------------------------------------------------------------------------
int test_validate_tool_call_definitions() {
    rac_tool_parameter_t params[2] = {
        {"location", RAC_TOOL_PARAM_STRING, "City name", RAC_TRUE, nullptr},
        {"unit", RAC_TOOL_PARAM_STRING, "Temperature unit", RAC_FALSE,
         R"(["celsius","fahrenheit"])"},
    };
    rac_tool_definition_t tools[1] = {
        {"get_weather", "Get weather for a city", params, 2, "weather"},
    };

    rac_tool_call_t parsed;
    rac_result_t rc = rac_tool_call_parse(
        "<tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\","
        "\"unit\":\"celsius\"}}</tool_call>",
        &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);

    rac_tool_call_validation_t validation;
    rc = rac_tool_call_validate(&parsed, tools, 1, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_TRUE);
    ASSERT_SUBSTR(validation.validation_errors_json, "[]");
    ASSERT_SUBSTR(validation.normalized_arguments_json, "\"location\":\"Tokyo\"");
    ASSERT_SUBSTR(validation.matched_tool_json, "\"get_weather\"");
    rac_tool_call_validation_free(&validation);
    rac_tool_call_free(&parsed);

    rc = rac_tool_call_parse(
        R"(<tool_call>{"tool":"get_weather","arguments":{"unit":"kelvin"}}</tool_call>)", &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    rc = rac_tool_call_validate(&parsed, tools, 1, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
    ASSERT_SUBSTR(validation.validation_errors_json, "Missing required argument: location");
    ASSERT_TRUE(validation.error_message != nullptr);
    rac_tool_call_validation_free(&validation);
    rac_tool_call_free(&parsed);
    return 0;
}

// ---------------------------------------------------------------------------
// 12. validate parsed call against generated-style JSON definitions
// ---------------------------------------------------------------------------
int test_validate_tool_call_json_definitions() {
    const char* tools_json =
        "[{\"name\":\"set_mode\",\"description\":\"Set mode\",\"parameters\":["
        "{\"name\":\"enabled\",\"type\":\"boolean\",\"required\":true},"
        "{\"name\":\"mode\",\"type\":\"string\",\"required\":true,"
        "\"enum_values\":[\"fast\",\"safe\"]}]}]";

    rac_tool_call_t parsed;
    rac_result_t rc = rac_tool_call_parse(
        "<tool_call>{\"tool\":\"set_mode\",\"arguments\":{\"enabled\":true,"
        "\"mode\":\"fast\"}}</tool_call>",
        &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);

    rac_tool_call_validation_t validation;
    rc = rac_tool_call_validate_json(&parsed, tools_json, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_TRUE);
    ASSERT_SUBSTR(validation.normalized_arguments_json, "\"enabled\":true");
    rac_tool_call_validation_free(&validation);
    rac_tool_call_free(&parsed);

    rc = rac_tool_call_parse(
        "<tool_call>{\"tool\":\"set_mode\",\"arguments\":{\"enabled\":\"yes\","
        "\"mode\":\"turbo\"}}</tool_call>",
        &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    rc = rac_tool_call_validate_json(&parsed, tools_json, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
    ASSERT_SUBSTR(validation.validation_errors_json, "enabled");
    ASSERT_SUBSTR(validation.validation_errors_json, "mode");
    rac_tool_call_validation_free(&validation);
    rac_tool_call_free(&parsed);
    return 0;
}

// ---------------------------------------------------------------------------
// 13. generated proto ABI: parse ToolParseRequest -> ToolParseResult
// ---------------------------------------------------------------------------
int test_parse_proto_round_trip() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolParseRequest request;
    request.set_text(
        "checking "
        "<tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Tokyo\"}}</tool_call>");
    request.mutable_options()->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);

    std::string request_bytes;
    ASSERT_TRUE(request.SerializeToString(&request_bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    const rac_result_t rc =
        rac_tool_call_parse_proto(reinterpret_cast<const uint8_t*>(request_bytes.data()),
                                  request_bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    ASSERT_TRUE(result_bytes.data != nullptr);

    runanywhere::v1::ToolParseResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.has_tool_call(), true);
    ASSERT_EQ_INT(result.tool_calls_size(), 1);
    ASSERT_EQ_STR(result.tool_calls(0).name().c_str(), "get_weather");
    ASSERT_SUBSTR(result.tool_calls(0).arguments_json().c_str(), "Tokyo");
    ASSERT_SUBSTR(result.remaining_text().c_str(), "checking");

    rac_proto_buffer_free(&result_bytes);
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// 14. generated proto ABI: format ToolPromptFormatRequest -> Result
// ---------------------------------------------------------------------------
int test_format_prompt_proto_round_trip() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    for (const auto format : {runanywhere::v1::TOOL_CALL_FORMAT_NAME_LFM2,
                              runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON}) {
        runanywhere::v1::ToolPromptFormatRequest request;
        request.set_user_prompt("Invoke the typed tool with every required argument.");
        auto* options = request.mutable_options();
        options->set_format(format);
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
        options->set_forced_tool_name("typed_tool");
        options->set_require_json_arguments(true);
        auto* tool = options->add_tools();
        tool->set_name("typed_tool");
        tool->set_description("Exercise every portable parameter type");
        // ToolDefinition.parameters is now ONE JSON Schema object string
        // (idl/tool_calling.proto, tools-one-json-schema) — the typed
        // ToolParameter message / ToolParameterType enum were deleted
        // outright. "unspecified" has no JSON Schema `type` keyword
        // equivalent, so the fallback parameter is declared with no type
        // (schema-valid: any value), matching what the old UNSPECIFIED enum
        // value meant (no type constraint).
        tool->set_parameters(
            R"({"type":"object","properties":{)"
            R"("text":{"type":"string"},)"
            R"("score":{"type":"number"},)"
            R"("enabled":{"type":"boolean"},)"
            R"("metadata":{"type":"object"},)"
            R"("items":{"type":"array"},)"
            R"("fallback":{}},)"
            R"("required":["text","score","enabled","metadata","items","fallback"]})");

        std::string request_bytes;
        ASSERT_TRUE(request.SerializeToString(&request_bytes));

        rac_proto_buffer_t result_bytes{};
        rac_proto_buffer_init(&result_bytes);
        rac_result_t rc = rac_tool_call_format_prompt_proto(
            reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
            &result_bytes);
        ASSERT_EQ_INT(rc, RAC_SUCCESS);
        ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
        ASSERT_TRUE(result_bytes.data != nullptr);

        runanywhere::v1::ToolPromptFormatResult format_result;
        ASSERT_TRUE(
            format_result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
        ASSERT_EQ_INT(format_result.error_code(), RAC_SUCCESS);
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "typed_tool");
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"type\":\"string\"");
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"type\":\"number\"");
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"type\":\"boolean\"");
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"type\":\"object\"");
        ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"type\":\"array\"");
        rac_proto_buffer_free(&result_bytes);

        std::string model_output;
        if (format == runanywhere::v1::TOOL_CALL_FORMAT_NAME_LFM2) {
            ASSERT_EQ_INT(format_result.format(), runanywhere::v1::TOOL_CALL_FORMAT_NAME_LFM2);
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "score=0");
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "enabled=true");
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "metadata={}");
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "items=[]");
            model_output =
                R"(<|tool_call_start|>[typed_tool(text="hello, world", score=12.5, enabled=true, metadata={"nested":{"values":[1,2]},"label":"x,y"}, items=[{"id":1},{"id":2}], fallback="plain")]<|tool_call_end|>)";
        } else {
            ASSERT_EQ_INT(format_result.format(), runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"metadata\":{}");
            ASSERT_SUBSTR(format_result.formatted_prompt().c_str(), "\"items\":[]");
            model_output =
                R"(<tool_call>{"tool":"typed_tool","arguments":{"text":"hello, world","score":12.5,"enabled":true,"metadata":{"nested":{"values":[1,2]},"label":"x,y"},"items":[{"id":1},{"id":2}],"fallback":"plain"}}</tool_call>)";
        }

        runanywhere::v1::ToolParseRequest parse_request;
        parse_request.set_text(model_output);
        *parse_request.mutable_options() = *options;
        std::string parse_bytes;
        ASSERT_TRUE(parse_request.SerializeToString(&parse_bytes));
        rac_proto_buffer_init(&result_bytes);
        rc = rac_tool_call_parse_proto(reinterpret_cast<const uint8_t*>(parse_bytes.data()),
                                       parse_bytes.size(), &result_bytes);
        ASSERT_EQ_INT(rc, RAC_SUCCESS);
        runanywhere::v1::ToolParseResult parse_result;
        ASSERT_TRUE(
            parse_result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
        ASSERT_EQ_INT(parse_result.has_tool_call(), true);
        ASSERT_EQ_INT(parse_result.tool_calls_size(), 1);
        ASSERT_EQ_STR(parse_result.tool_calls(0).name().c_str(), "typed_tool");
        ASSERT_SUBSTR(parse_result.tool_calls(0).arguments_json().c_str(), "\"score\":12.5");
        ASSERT_SUBSTR(parse_result.tool_calls(0).arguments_json().c_str(), "\"enabled\":true");
        ASSERT_SUBSTR(parse_result.tool_calls(0).arguments_json().c_str(), "\"nested\"");
        ASSERT_SUBSTR(parse_result.tool_calls(0).arguments_json().c_str(), "\"items\":[{");
        rac_proto_buffer_free(&result_bytes);

        runanywhere::v1::ToolCallValidationRequest validation_request;
        *validation_request.mutable_tool_call() = parse_result.tool_calls(0);
        *validation_request.mutable_options() = *options;
        std::string validation_bytes;
        ASSERT_TRUE(validation_request.SerializeToString(&validation_bytes));
        rac_proto_buffer_init(&result_bytes);
        rc = rac_tool_call_validate_proto(reinterpret_cast<const uint8_t*>(validation_bytes.data()),
                                          validation_bytes.size(), &result_bytes);
        ASSERT_EQ_INT(rc, RAC_SUCCESS);
        runanywhere::v1::ToolCallValidationResult validation_result;
        ASSERT_TRUE(validation_result.ParseFromArray(result_bytes.data,
                                                     static_cast<int>(result_bytes.size)));
        if (!validation_result.is_valid()) {
            std::fprintf(stderr, "typed arguments: %s\n",
                         parse_result.tool_calls(0).arguments_json().c_str());
            for (const auto& error : validation_result.validation_errors()) {
                std::fprintf(stderr, "typed validation error: %s\n", error.c_str());
            }
        }
        ASSERT_EQ_INT(validation_result.is_valid(), true);
        ASSERT_EQ_INT(validation_result.validation_errors_size(), 0);
        rac_proto_buffer_free(&result_bytes);
    }
    return 0;
#endif
}

int test_format_specific_zero_parameter_prompt() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt("Call get_current_time now.");
    auto* options = request.mutable_options();
    options->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    options->set_forced_tool_name("get_current_time");
    auto* tool = options->add_tools();
    tool->set_name("get_current_time");
    tool->set_description("Get the current time");

    std::string request_bytes;
    ASSERT_TRUE(request.SerializeToString(&request_bytes));
    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    const rac_result_t rc = rac_tool_call_format_prompt_proto(
        reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    runanywhere::v1::ToolPromptFormatResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_SUBSTR(result.formatted_prompt().c_str(),
                  "<tool_call>{\"tool\":\"get_current_time\"}</tool_call>");
    ASSERT_TRUE(std::strstr(result.formatted_prompt().c_str(), "\"arguments\"") == nullptr);
    rac_proto_buffer_free(&result_bytes);
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// 15. generated proto ABI: validate ToolCallValidationRequest -> Result
// ---------------------------------------------------------------------------
int test_validate_proto_round_trip() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolCallValidationRequest request;
    auto* call = request.mutable_tool_call();
    call->set_name("set_mode");
    call->set_arguments_json(R"({"enabled":true,"mode":"safe"})");

    auto* options = request.mutable_options();
    options->set_require_json_arguments(true);
    auto* tool = options->add_tools();
    tool->set_name("set_mode");
    tool->set_description("Set runtime mode");
    // ToolDefinition.parameters is now ONE JSON Schema object string
    // (idl/tool_calling.proto, tools-one-json-schema) — the typed
    // ToolParameter message / ToolParameterType enum were deleted outright.
    tool->set_parameters(
        R"({"type":"object","properties":{)"
        R"("enabled":{"type":"boolean"},)"
        R"("mode":{"type":"string","enum":["fast","safe"]}},)"
        R"("required":["enabled","mode"]})");

    std::string request_bytes;
    ASSERT_TRUE(request.SerializeToString(&request_bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    const rac_result_t rc =
        rac_tool_call_validate_proto(reinterpret_cast<const uint8_t*>(request_bytes.data()),
                                     request_bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    ASSERT_TRUE(result_bytes.data != nullptr);

    runanywhere::v1::ToolCallValidationResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.is_valid(), true);
    ASSERT_EQ_INT(result.error_code(), RAC_SUCCESS);
    ASSERT_EQ_INT(result.validation_errors_size(), 0);
    ASSERT_TRUE(result.has_matched_tool());
    ASSERT_EQ_STR(result.matched_tool().name().c_str(), "set_mode");
    ASSERT_SUBSTR(result.normalized_arguments_json().c_str(), "\"enabled\":true");
    ASSERT_SUBSTR(result.normalized_arguments_json().c_str(), "\"mode\":\"safe\"");

    rac_proto_buffer_free(&result_bytes);
    return 0;
#endif
}

#if defined(RAC_HAVE_PROTOBUF)
// Drives rac_tool_call_format_prompt_proto and returns the formatted prompt.
std::string format_prompt_via_proto(const runanywhere::v1::ToolPromptFormatRequest& request) {
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return {};
    }
    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    std::string out;
    if (rac_tool_call_format_prompt_proto(reinterpret_cast<const uint8_t*>(request_bytes.data()),
                                          request_bytes.size(), &result_bytes) == RAC_SUCCESS &&
        result_bytes.data != nullptr) {
        runanywhere::v1::ToolPromptFormatResult format_result;
        if (format_result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size))) {
            out = format_result.formatted_prompt();
        }
    }
    rac_proto_buffer_free(&result_bytes);
    return out;
}

runanywhere::v1::ToolDefinition make_named_tool(const char* name) {
    runanywhere::v1::ToolDefinition tool;
    tool.set_name(name);
    tool.set_description("test tool");
    // ToolDefinition.parameters is now ONE JSON Schema object string
    // (idl/tool_calling.proto, tools-one-json-schema).
    tool.set_parameters(R"({"type":"object","properties":{"q":{"type":"string"}},)"
                        R"("required":["q"]})");
    return tool;
}
#endif

// RUN-80 (review follow-up): tool_choice=REQUIRED appends one firm directive on
// the initial tool-advertising turn, and ONLY there — never for AUTO/NONE nor on
// a follow-up (tool_results present).
int test_required_appends_firm_directive() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    const char* kFirm = "You must call exactly one tool now.";
    const auto build = [](runanywhere::v1::ToolChoiceMode choice, bool with_result) {
        runanywhere::v1::ToolPromptFormatRequest req;
        req.set_user_prompt("Do the thing.");
        auto* opt = req.mutable_options();
        opt->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
        opt->set_tool_choice(choice);
        *opt->add_tools() = make_named_tool("do_thing");
        if (with_result) {
            auto* tr = req.add_tool_results();
            tr->set_name("do_thing");
            tr->set_result_json("{\"ok\":true}");
        }
        return req;
    };

    ASSERT_TRUE(format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED, false))
                    .find(kFirm) != std::string::npos);
    ASSERT_TRUE(format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_AUTO, false))
                    .find(kFirm) == std::string::npos);
    ASSERT_TRUE(format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_NONE, false))
                    .find(kFirm) == std::string::npos);
    // REQUIRED follow-up turn (tool already ran) must NOT re-demand a call.
    ASSERT_TRUE(format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED, true))
                    .find(kFirm) == std::string::npos);
    return 0;
#endif
}

// RUN-80 (review follow-up): a tool_choice=NONE follow-up (tool_results present)
// never re-advertises the tools body nor invites "use another tool", even when
// the caller set keep_tools_available — across both the single- and multi-result
// paths. Positive control: keep_tools_available WITHOUT NONE re-advertises.
int test_none_followup_suppresses_tools() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    const auto build = [](runanywhere::v1::ToolChoiceMode choice, int num_results) {
        runanywhere::v1::ToolPromptFormatRequest req;
        req.set_user_prompt("Summarize the results.");
        auto* opt = req.mutable_options();
        opt->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
        opt->set_tool_choice(choice);
        opt->set_keep_tools_available(true);
        *opt->add_tools() = make_named_tool("do_thing");
        for (int i = 0; i < num_results; ++i) {
            auto* tr = req.add_tool_results();
            tr->set_name("do_thing");
            tr->set_result_json("{\"ok\":true}");
        }
        return req;
    };

    // NONE single-result follow-up: the tools body is NOT re-advertised.
    {
        const std::string p = format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_NONE, 1));
        ASSERT_TRUE(p.find("# TOOLS") == std::string::npos);
        ASSERT_TRUE(p.find("You may use another tool") == std::string::npos);
    }
    // NONE multi-result follow-up: same suppression + explicit "Do not emit" text.
    {
        const std::string p = format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_NONE, 2));
        ASSERT_TRUE(p.find("# TOOLS") == std::string::npos);
        ASSERT_TRUE(p.find("Do not emit tool calls") != std::string::npos);
        ASSERT_TRUE(p.find("You may use another tool") == std::string::npos);
    }
    // Positive control: keep_tools_available WITHOUT NONE re-advertises the tools.
    {
        const std::string p = format_prompt_via_proto(build(runanywhere::v1::TOOL_CHOICE_MODE_AUTO, 1));
        ASSERT_TRUE(p.find("# TOOLS") != std::string::npos);
    }
    return 0;
#endif
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
        {.name = "parse_default_structured", .fn = test_parse_default_structured},
        {.name = "parse_default_nested_keys_stay_arguments",
         .fn = test_parse_default_nested_keys_stay_arguments},
        {.name = "parse_lfm2_structured", .fn = test_parse_lfm2_structured},
        {.name = "parse_lfm2_invalid_utf8", .fn = test_parse_lfm2_invalid_utf8},
        {.name = "parse_free_form_returns_false", .fn = test_parse_free_form_returns_false},
        {.name = "format_prompt_default_two_tools", .fn = test_format_prompt_default_two_tools},
        {.name = "format_prompt_json_lfm2", .fn = test_format_prompt_json_lfm2},
        {.name = "build_initial_prompt_e2e", .fn = test_build_initial_prompt_end_to_end},
        {.name = "build_followup_prompt_no_tools", .fn = test_build_followup_prompt_no_tools},
        {.name = "build_followup_prompt_keep_tools", .fn = test_build_followup_prompt_keep_tools},
        {.name = "build_search_web_followup_prompt", .fn = test_build_search_web_followup_prompt},
        {.name = "normalize_json_unquoted_keys", .fn = test_normalize_json_unquoted_keys},
        {.name = "free_functions_idempotent", .fn = test_free_functions_idempotent},
        {.name = "format_name_round_trip", .fn = test_format_name_round_trip},
        {.name = "tool_call_format_per_family", .fn = test_tool_call_format_per_family},
        {.name = "pythonic_detect_and_parse", .fn = test_pythonic_detect_and_parse},
        {.name = "pythonic_utf8_strings", .fn = test_pythonic_utf8_strings},
        {.name = "pythonic_utf8_nested_values", .fn = test_pythonic_utf8_nested_values},
        {.name = "pythonic_utf8_invalid_scalars", .fn = test_pythonic_utf8_invalid_scalars},
        {.name = "pythonic_utf8_valid_unicode", .fn = test_pythonic_utf8_valid_unicode},
        {.name = "pythonic_utf8_argument_key", .fn = test_pythonic_utf8_argument_key},
        {.name = "validate_invalid_utf8_tool_name", .fn = test_validate_invalid_utf8_tool_name},
#if defined(RAC_HAVE_PROTOBUF)
        {.name = "tool_result_utf8_error_payload", .fn = test_tool_result_utf8_error_payload},
#endif
        {.name = "parse_pythonic_invalid_utf8", .fn = test_parse_pythonic_invalid_utf8},
        {.name = "pythonic_multibracket_and_special_args",
         .fn = test_pythonic_multibracket_and_special_args},
        {.name = "pythonic_prompt_render", .fn = test_pythonic_prompt_render},
        {.name = "required_appends_firm_directive", .fn = test_required_appends_firm_directive},
        {.name = "none_followup_suppresses_tools", .fn = test_none_followup_suppresses_tools},
        {.name = "tool_result_loop", .fn = test_tool_result_loop},
        {.name = "validate_tool_call_definitions", .fn = test_validate_tool_call_definitions},
        {.name = "validate_tool_call_json_definitions",
         .fn = test_validate_tool_call_json_definitions},
        {.name = "parse_proto_round_trip", .fn = test_parse_proto_round_trip},
        {.name = "format_prompt_proto_round_trip", .fn = test_format_prompt_proto_round_trip},
        {.name = "format_specific_zero_parameter_prompt",
         .fn = test_format_specific_zero_parameter_prompt},
        {.name = "validate_proto_round_trip", .fn = test_validate_proto_round_trip},
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
