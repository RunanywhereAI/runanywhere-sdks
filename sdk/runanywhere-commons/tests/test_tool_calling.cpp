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
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "features/llm/tool_calling_internal.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
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
        const auto add_parameter = [tool](const char* name,
                                          runanywhere::v1::ToolParameterType type) {
            auto* parameter = tool->add_parameters();
            parameter->set_name(name);
            parameter->set_type(type);
            parameter->set_required(true);
        };
        add_parameter("text", runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
        add_parameter("score", runanywhere::v1::TOOL_PARAMETER_TYPE_NUMBER);
        add_parameter("enabled", runanywhere::v1::TOOL_PARAMETER_TYPE_BOOLEAN);
        add_parameter("metadata", runanywhere::v1::TOOL_PARAMETER_TYPE_OBJECT);
        add_parameter("items", runanywhere::v1::TOOL_PARAMETER_TYPE_ARRAY);
        add_parameter("fallback", runanywhere::v1::TOOL_PARAMETER_TYPE_UNSPECIFIED);

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
    auto* enabled = tool->add_parameters();
    enabled->set_name("enabled");
    enabled->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_BOOLEAN);
    enabled->set_required(true);
    auto* mode = tool->add_parameters();
    mode->set_name("mode");
    mode->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
    mode->set_required(true);
    mode->add_enum_values("fast");
    mode->add_enum_values("safe");

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
        {.name = "parse_lfm2_structured", .fn = test_parse_lfm2_structured},
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
        {.name = "tool_result_loop", .fn = test_tool_result_loop},
        {.name = "validate_tool_call_definitions", .fn = test_validate_tool_call_definitions},
        {.name = "validate_tool_call_json_definitions",
         .fn = test_validate_tool_call_json_definitions},
        {.name = "parse_proto_round_trip", .fn = test_parse_proto_round_trip},
        {.name = "format_prompt_proto_round_trip", .fn = test_format_prompt_proto_round_trip},
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
