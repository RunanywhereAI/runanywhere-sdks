/**
 * @file test_agent_loop_converter.cpp
 * @brief AG-2: verifies expand_agent_loop routes a tools-bearing
 * AgentLoopConfig to the `agent_loop` operator (with tool params consumed)
 * and keeps the historical `generate_text` operator when no tools are set.
 */

#include <cstdio>
#include <string>

#if defined(RAC_HAVE_PROTOBUF)
#include "pipeline.pb.h"
#include "solutions.pb.h"

#include "rac/solutions/solution_converter.hpp"
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

const runanywhere::v1::OperatorSpec* find_op(const runanywhere::v1::PipelineSpec& spec,
                                             const std::string& name) {
    for (const auto& op : spec.operators()) {
        if (op.name() == name) {
            return &op;
        }
    }
    return nullptr;
}

std::string param_or_empty(const runanywhere::v1::OperatorSpec& op, const std::string& key) {
    const auto it = op.params().find(key);
    return it == op.params().end() ? std::string() : it->second;
}

void test_tools_config_emits_agent_loop_op() {
    runanywhere::v1::SolutionConfig config;
    auto* agent = config.mutable_agent_loop();
    agent->set_llm_model_id("test-model");
    agent->set_system_prompt("be helpful");
    agent->set_max_iterations(4);
    auto* tool = agent->add_tools();
    tool->set_name("get_weather");
    tool->set_description("weather lookup");
    tool->set_json_schema("{\"type\":\"object\"}");

    runanywhere::v1::PipelineSpec spec;
    const rac_result_t rc = rac::solutions::convert_solution_to_pipeline(config, &spec);
    CHECK(rc == RAC_SUCCESS, "tools config converts successfully");

    const auto* llm = find_op(spec, "llm");
    CHECK(llm != nullptr, "llm op exists");
    if (llm == nullptr) {
        return;
    }
    CHECK(llm->type() == "agent_loop", "tools present -> op type is agent_loop");
    CHECK(param_or_empty(*llm, "tool.count") == "1", "tool.count param carries the tool set size");
    CHECK(param_or_empty(*llm, "tool.0.name") == "get_weather", "tool name param forwarded");
    CHECK(param_or_empty(*llm, "tool.0.description") == "weather lookup",
          "tool description param forwarded");
    CHECK(param_or_empty(*llm, "tool.0.json_schema") == "{\"type\":\"object\"}",
          "tool schema param forwarded");
    CHECK(param_or_empty(*llm, "max_iterations") == "4", "max_iterations param forwarded");
    CHECK(param_or_empty(*llm, "system_prompt") == "be helpful", "system_prompt param forwarded");
}

void test_toolless_config_keeps_generate_text() {
    runanywhere::v1::SolutionConfig config;
    auto* agent = config.mutable_agent_loop();
    agent->set_llm_model_id("test-model");
    agent->set_system_prompt("be helpful");

    runanywhere::v1::PipelineSpec spec;
    const rac_result_t rc = rac::solutions::convert_solution_to_pipeline(config, &spec);
    CHECK(rc == RAC_SUCCESS, "tool-less config converts successfully");

    const auto* llm = find_op(spec, "llm");
    CHECK(llm != nullptr, "llm op exists (tool-less)");
    if (llm != nullptr) {
        CHECK(llm->type() == "generate_text", "no tools -> historical generate_text op retained");
        CHECK(param_or_empty(*llm, "tool.count").empty(), "no tool params emitted without tools");
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
#if defined(RAC_HAVE_PROTOBUF)
    test_tools_config_emits_agent_loop_op();
    test_toolless_config_keeps_generate_text();
#else
    std::fprintf(stdout, "  skip: RAC_HAVE_PROTOBUF not defined\n");
#endif

    std::fprintf(stdout, "\n%d/%d checks passed\n", test_count - fail_count, test_count);
    return fail_count == 0 ? 0 : 1;
}
