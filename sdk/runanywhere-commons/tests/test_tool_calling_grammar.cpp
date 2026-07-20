/**
 * @file test_tool_calling_grammar.cpp
 * @brief TC-1: verifies build_tool_call_grammar() derives the correct
 * grammar dialect content for each tool_choice policy — a pure function
 * over ToolCallingOptions, so no mock LLM plugin / lifecycle is needed.
 */

#include <cstdio>
#include <cstring>
#include <string>

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"

#include <vector>

#include "features/llm/tool_calling_grammar.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                           \
    do {                                                                             \
        ++test_count;                                                                \
        if (!(cond)) {                                                               \
            ++fail_count;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        } else {                                                                     \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        }                                                                            \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

runanywhere::v1::ToolCallingOptions two_tool_options() {
    runanywhere::v1::ToolCallingOptions options;
    auto* a = options.add_tools();
    a->set_name("get_weather");
    a->set_description("Gets current weather");
    auto* b = options.add_tools();
    b->set_name("get_current_time");
    b->set_description("Gets current time");
    return options;
}

void test_none_tools_yields_empty_grammar() {
    runanywhere::v1::ToolCallingOptions empty_options;
    auto grammar = rac::llm::tool_calling::build_tool_call_grammar(
        empty_options, /*has_tool_choice=*/false, runanywhere::v1::TOOL_CHOICE_MODE_UNSPECIFIED,
        /*forced_tool_name=*/"");
    CHECK(grammar.gbnf.empty() && grammar.qhexrt.empty(), "empty tool set -> no grammar");

    auto options = two_tool_options();
    auto none_grammar = rac::llm::tool_calling::build_tool_call_grammar(
        options, /*has_tool_choice=*/true, runanywhere::v1::TOOL_CHOICE_MODE_NONE,
        /*forced_tool_name=*/"");
    CHECK(none_grammar.gbnf.empty() && none_grammar.qhexrt.empty(),
          "tool_choice=NONE -> no grammar");
}

void test_auto_leaves_gbnf_unconstrained_but_sets_qhexrt_opt() {
    auto options = two_tool_options();
    auto grammar = rac::llm::tool_calling::build_tool_call_grammar(
        options, /*has_tool_choice=*/false, runanywhere::v1::TOOL_CHOICE_MODE_AUTO,
        /*forced_tool_name=*/"");
    CHECK(grammar.gbnf.empty(), "AUTO -> llamacpp dialect left unconstrained");
    CHECK(grammar.qhexrt == "toolcall_opt:get_weather,get_current_time",
          "AUTO -> qhexrt dialect is toolcall_opt: with both names");
}

void test_required_constrains_both_dialects_over_all_names() {
    auto options = two_tool_options();
    auto grammar = rac::llm::tool_calling::build_tool_call_grammar(
        options, /*has_tool_choice=*/true, runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED,
        /*forced_tool_name=*/"");
    CHECK(grammar.qhexrt == "toolcall:get_weather,get_current_time",
          "REQUIRED -> qhexrt dialect is toolcall: with both names");

    CHECK(!grammar.gbnf.empty(), "REQUIRED -> llamacpp GBNF is non-empty");
    CHECK(grammar.gbnf.find("root ::=") != std::string::npos, "GBNF declares a root rule");
    CHECK(grammar.gbnf.find("<tool_call>{\\\"tool\\\":") != std::string::npos,
          "GBNF root matches the <tool_call>{\"tool\": envelope prefix");
    CHECK(grammar.gbnf.find("}</tool_call>") != std::string::npos,
          "GBNF root matches the }</tool_call> envelope suffix");
    CHECK(grammar.gbnf.find(R"("\"get_weather\"")") != std::string::npos,
          "GBNF tool-name alternation includes get_weather");
    CHECK(grammar.gbnf.find(R"("\"get_current_time\"")") != std::string::npos,
          "GBNF tool-name alternation includes get_current_time");
    CHECK(grammar.gbnf.find("object ::=") != std::string::npos,
          "GBNF appends the permissive JSON object production for arguments");
}

void test_specific_constrains_to_single_forced_name() {
    auto options = two_tool_options();
    auto grammar = rac::llm::tool_calling::build_tool_call_grammar(
        options, /*has_tool_choice=*/true, runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC,
        /*forced_tool_name=*/"get_weather");
    CHECK(grammar.qhexrt == "toolcall:get_weather",
          "SPECIFIC -> qhexrt dialect names only the forced tool");
    CHECK(grammar.gbnf.find(R"("\"get_weather\"")") != std::string::npos,
          "SPECIFIC GBNF includes the forced tool name");
    CHECK(grammar.gbnf.find(R"("\"get_current_time\"")") == std::string::npos,
          "SPECIFIC GBNF excludes the non-forced tool name");
}

// TC-2: rac_tool_call_parse_proto returns every envelope in one output when
// parallel_tool_calls is set, and only the first when it is not.
void test_parallel_parse_returns_all_envelopes() {
    const char* two_calls =
        "<tool_call>{\"tool\":\"get_weather\",\"arguments\":{\"location\":\"Ankara\"}}</tool_call>"
        "<tool_call>{\"tool\":\"get_current_time\",\"arguments\":{}}</tool_call>";

    const auto parse_with = [&](bool parallel) -> runanywhere::v1::ToolParseResult {
        runanywhere::v1::ToolParseRequest request;
        request.set_text(two_calls);
        request.mutable_options()->set_parallel_tool_calls(parallel);
        std::vector<uint8_t> bytes(request.ByteSizeLong());
        request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()));

        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        runanywhere::v1::ToolParseResult result;
        if (rac_tool_call_parse_proto(bytes.data(), bytes.size(), &out) == RAC_SUCCESS &&
            out.data != nullptr) {
            result.ParseFromArray(out.data, static_cast<int>(out.size));
        }
        rac_proto_buffer_free(&out);
        return result;
    };

    const auto serial = parse_with(false);
    CHECK(serial.tool_calls_size() == 1, "parallel off -> single call parsed (legacy behavior)");

    const auto parallel = parse_with(true);
    CHECK(parallel.tool_calls_size() == 2, "parallel on -> both envelopes parsed");
    if (parallel.tool_calls_size() == 2) {
        CHECK(parallel.tool_calls(0).name() == "get_weather", "first parallel call is get_weather");
        CHECK(parallel.tool_calls(1).name() == "get_current_time",
              "second parallel call is get_current_time");
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
#if defined(RAC_HAVE_PROTOBUF)
    test_none_tools_yields_empty_grammar();
    test_auto_leaves_gbnf_unconstrained_but_sets_qhexrt_opt();
    test_required_constrains_both_dialects_over_all_names();
    test_specific_constrains_to_single_forced_name();
    test_parallel_parse_returns_all_envelopes();
#else
    std::fprintf(stdout, "  skip: RAC_HAVE_PROTOBUF not defined\n");
#endif

    std::fprintf(stdout, "\n%d/%d checks passed\n", test_count - fail_count, test_count);
    return fail_count == 0 ? 0 : 1;
}
