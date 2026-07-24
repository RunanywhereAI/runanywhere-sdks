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
    ASSERT_EQ(static_cast<int>(a.type), static_cast<int>(RAC_CUA_LEFT_CLICK), "action = left_click");
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

TestResult run_malformed_not_ok() {
    rac_cua_action_t a;
    int rc = rac_cua_parse_action(RAC_CUA_PROFILE_FARA, "just some prose, no tool call", 100, 100, &a);
    ASSERT_EQ(rc, 0, "recognized profile still returns 0");
    ASSERT_EQ(static_cast<int>(a.parse_ok), 0, "no tool_call -> parse_ok = 0");
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("cua");
    suite.add("fara_prompt_has_schema", run_fara_prompt_has_schema);
    suite.add("unknown_profile_rejected", run_unknown_profile_rejected);
    suite.add("golden_left_click", run_golden_left_click);
    suite.add("type_action_text", run_type_action_text);
    suite.add("terminate_answer", run_terminate_answer);
    suite.add("malformed_not_ok", run_malformed_not_ok);
    return suite.run(argc, argv);
}
