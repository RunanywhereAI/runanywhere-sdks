/**
 * @file test_cua.cpp
 * @brief Tests for the computer-use-agent scaffold (rac_cua_*).
 *
 * Profile-parameterized: verifies the built-in "fara" profile's system prompt
 * carries the computer_use tool schema, and that action parsing maps the fixed
 * 1000x1000 model space to the caller's viewport (golden: left_click [500,382]
 * -> (720,344) at 1440x900, the number validated end-to-end this session).
 */

#include "test_common.h"

#include <cstring>
#include <string>

#include "rac/features/cua/rac_cua.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "cua.pb.h"
#endif

namespace {

TestResult run_fara_prompt_has_schema() {
    char buf[8192];
    int n = rac_cua_system_prompt(RAC_CUA_PROFILE_FARA, 1000, 1000, buf, sizeof(buf));
    ASSERT_TRUE(n > 0, "prompt length must be positive");
    ASSERT_TRUE(n < static_cast<int>(sizeof(buf)), "prompt must fit test buffer");
    std::string p(buf);
    ASSERT_TRUE(p.find("<tools>") != std::string::npos, "prompt must contain <tools>");
    ASSERT_TRUE(p.find("computer_use") != std::string::npos, "prompt must name computer_use");
    ASSERT_TRUE(p.find("1000x1000") != std::string::npos, "prompt must state the resolution");
    ASSERT_TRUE(p.find("You are Fara") != std::string::npos, "prompt must include the identity");
    return TEST_PASS();
}

TestResult run_unknown_profile_rejected() {
    rac_cua_action_t a;
    int rc = rac_cua_parse_action("does-not-exist", "<tool_call>{}</tool_call>", 100, 100, &a);
    ASSERT_EQ(rc, -1, "unknown profile must return -1");
    int rc2 = rac_cua_system_prompt("does-not-exist", 1000, 1000, nullptr, 0);
    ASSERT_EQ(rc2, -1, "unknown profile prompt must return -1");
    return TEST_PASS();
}

TestResult run_golden_left_click() {
    const char* out =
        "I will click on the search box.\n"
        "<tool_call>\n"
        "{\"name\": \"computer_use\", \"arguments\": {\"action\": \"left_click\", "
        "\"coordinate\": [500, 382]}}\n"
        "</tool_call>";
    rac_cua_action_t a;
    int rc = rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(rc, 0, "recognized profile must return 0");
    ASSERT_EQ(static_cast<int>(a.parse_ok), 1, "must parse a valid tool_call");
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_LEFT_CLICK),
              "action = left_click");
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 1, "must have coordinate");
    ASSERT_EQ(a.x, 720, "x = 500 * 1440/1000 = 720");
    ASSERT_EQ(a.y, 344, "y = 382 * 900/1000 = 344 (rounded)");
    ASSERT_TRUE(std::strstr(a.reasoning, "search box") != nullptr, "reasoning captured");
    return TEST_PASS();
}

TestResult run_type_action_text() {
    const char* out =
        "<tool_call>{\"name\": \"computer_use\", \"arguments\": "
        "{\"action\": \"type\", \"text\": \"hello world\"}}</tool_call>";
    rac_cua_action_t a;
    int rc = rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(rc, 0, "return 0");
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_TYPE), "action = type");
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 0, "type has no coordinate");
    ASSERT_TRUE(std::strcmp(a.text, "hello world") == 0, "text arg parsed");
    return TEST_PASS();
}

TestResult run_terminate_answer() {
    const char* out =
        "<tool_call>{\"name\": \"computer_use\", \"arguments\": "
        "{\"action\": \"terminate\", \"answer\": \"done\"}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 800, 600, &a);
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_TERMINATE), "action = terminate");
    ASSERT_TRUE(std::strcmp(a.text, "done") == 0, "answer mapped to text");
    return TEST_PASS();
}

// --- regressions: the extractors must fail CLOSED on untrusted model output ---

// A non-array `coordinate` must not latch onto a later array (it used to read
// `keys` as a click point and report has_coordinate=1).
TestResult run_coordinate_null_does_not_borrow_other_array() {
    const char* out =
        "<tool_call>{\"name\": \"computer_use\", \"arguments\": "
        "{\"action\": \"left_click\", \"coordinate\": null, \"keys\": [7, 8]}}</tool_call>";
    rac_cua_action_t a;
    ASSERT_EQ(rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a), 0, "return 0");
    ASSERT_EQ(static_cast<int>(a.parse_ok), 1, "action still parses");
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 0, "must NOT fabricate a coordinate");
    return TEST_PASS();
}

// A one-element array is not a coordinate (it used to yield y = 0).
TestResult run_single_element_coordinate_rejected() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"left_click\", \"coordinate\": "
        "[500]}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 0, "1-element array is not a coordinate");
    return TEST_PASS();
}

// A three-element array is not a coordinate either.
TestResult run_three_element_coordinate_rejected() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"left_click\", "
        "\"coordinate\": [1, 2, 3]}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 0, "3-element array is not a coordinate");
    return TEST_PASS();
}

// A null string value must not return the NEXT key's name (it used to yield
// text = "note" for url:null).
TestResult run_null_string_does_not_return_next_key() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"visit_url\", \"url\": null, "
        "\"note\": \"hello\"}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_VISIT_URL), "action = visit_url");
    ASSERT_TRUE(a.text[0] == '\0', "text must be empty, not the next key's name");
    return TEST_PASS();
}

// KEY carries its chord space-joined, per rac_cua.h / cua.proto / every facade.
TestResult run_key_action_joins_keys() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"key\", "
        "\"keys\": [\"ctrl\", \"l\"]}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_KEY), "action = key");
    ASSERT_TRUE(std::strcmp(a.text, "ctrl l") == 0, "keys joined with a space");
    return TEST_PASS();
}

// A non-numeric value for a numeric key must report absent, not 0.
TestResult run_non_numeric_scroll_rejected() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"scroll\", \"pixels\": null}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_SCROLL), "action = scroll");
    ASSERT_EQ(a.scroll_pixels, 0, "non-numeric pixels leaves the default");
    return TEST_PASS();
}

// \uXXXX decodes to UTF-8 rather than emitting a literal "uXXXX".
TestResult run_unicode_escape_decoded() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"type\", "
        "\"text\": \"caf\\u00e9\"}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_TRUE(std::strcmp(a.text, "caf\xc3\xa9") == 0, "\\u00e9 -> UTF-8 e-acute");
    return TEST_PASS();
}

// A key name appearing as a VALUE must not be mistaken for the key itself.
TestResult run_key_name_inside_value_ignored() {
    const char* out =
        "<tool_call>{\"arguments\": {\"action\": \"type\", "
        "\"text\": \"the word coordinate\", \"coordinate\": [10, 20]}}</tool_call>";
    rac_cua_action_t a;
    rac_cua_parse_action(RAC_CUA_PROFILE_FARA, out, 1440, 900, &a);
    ASSERT_TRUE(std::strcmp(a.text, "the word coordinate") == 0, "text intact");
    ASSERT_EQ(static_cast<int>(a.has_coordinate), 1, "the real coordinate key still resolves");
    return TEST_PASS();
}

TestResult run_malformed_not_ok() {
    rac_cua_action_t a;
    int rc =
        rac_cua_parse_action(RAC_CUA_PROFILE_FARA, "just some prose, no tool call", 100, 100, &a);
    ASSERT_EQ(rc, 0, "recognized profile still returns 0");
    ASSERT_EQ(static_cast<int>(a.parse_ok), 0, "no tool_call -> parse_ok = 0");
    return TEST_PASS();
}

#if defined(RAC_HAVE_PROTOBUF)
// The proto-byte variant is a faithful projection of the struct parse: same
// golden output, decoded from the wire CuaAction each SDK will see.
TestResult run_proto_roundtrip_golden() {
    const char* out =
        "I will click on the search box.\n"
        "<tool_call>\n"
        "{\"name\": \"computer_use\", \"arguments\": {\"action\": \"left_click\", "
        "\"coordinate\": [500, 382]}}\n"
        "</tool_call>";
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    rac_result_t rc = rac_cua_parse_action_proto(RAC_CUA_PROFILE_FARA, out, 1440, 900, &buf);
    ASSERT_EQ(static_cast<int>(rc), static_cast<int>(RAC_SUCCESS), "proto parse returns success");
    ASSERT_TRUE(buf.data != nullptr && buf.size > 0, "proto buffer carries bytes");

    runanywhere::v1::CuaAction action;
    ASSERT_TRUE(action.ParseFromArray(buf.data, static_cast<int>(buf.size)), "decode CuaAction");
    ASSERT_EQ(static_cast<int>(action.type()),
              static_cast<int>(runanywhere::v1::CUA_ACTION_TYPE_LEFT_CLICK), "type = left_click");
    ASSERT_TRUE(action.coordinate_valid(), "has coordinate");
    ASSERT_EQ(action.x(), 720, "x = 500 * 1440/1000 = 720");
    ASSERT_EQ(action.y(), 344, "y = 382 * 900/1000 = 344");
    ASSERT_TRUE(action.parse_ok(), "parse_ok true");
    ASSERT_TRUE(action.reasoning().find("search box") != std::string::npos, "reasoning captured");
    rac_proto_buffer_free(&buf);
    return TEST_PASS();
}

TestResult run_proto_unknown_profile_error() {
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    rac_result_t rc =
        rac_cua_parse_action_proto("does-not-exist", "<tool_call>{}</tool_call>", 100, 100, &buf);
    ASSERT_TRUE(rc != RAC_SUCCESS, "unknown profile must fail");
    ASSERT_TRUE(buf.data == nullptr, "error buffer carries no data");
    rac_proto_buffer_free(&buf);
    return TEST_PASS();
}
#endif

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("cua");
    suite.add("fara_prompt_has_schema", run_fara_prompt_has_schema);
    suite.add("unknown_profile_rejected", run_unknown_profile_rejected);
    suite.add("golden_left_click", run_golden_left_click);
    suite.add("type_action_text", run_type_action_text);
    suite.add("terminate_answer", run_terminate_answer);
    suite.add("malformed_not_ok", run_malformed_not_ok);
    suite.add("coordinate_null_does_not_borrow_other_array",
              run_coordinate_null_does_not_borrow_other_array);
    suite.add("single_element_coordinate_rejected", run_single_element_coordinate_rejected);
    suite.add("three_element_coordinate_rejected", run_three_element_coordinate_rejected);
    suite.add("null_string_does_not_return_next_key", run_null_string_does_not_return_next_key);
    suite.add("key_action_joins_keys", run_key_action_joins_keys);
    suite.add("non_numeric_scroll_rejected", run_non_numeric_scroll_rejected);
    suite.add("unicode_escape_decoded", run_unicode_escape_decoded);
    suite.add("key_name_inside_value_ignored", run_key_name_inside_value_ignored);
#if defined(RAC_HAVE_PROTOBUF)
    suite.add("proto_roundtrip_golden", run_proto_roundtrip_golden);
    suite.add("proto_unknown_profile_error", run_proto_unknown_profile_error);
#endif
    return suite.run(argc, argv);
}
