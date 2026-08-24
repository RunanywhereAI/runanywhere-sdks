// SPDX-License-Identifier: Apache-2.0
//
// test_agent_workflow.cpp — validation, ordering, and expression tests for the
// agent workflow runner.
//
// These cover the parts that are pure functions of a document: validation
// verdicts, topological order, Condition branch selection, and expression
// resolution. Executing a run needs a platform adapter and a loaded model, so
// it belongs in the app-level end-to-end pass rather than here.

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "agent_workflow.pb.h"

#include "../src/agent/bundle.h"
#include "../src/agent/expression.h"
#include "../src/agent/node_executors.h"
#include "../src/agent/workflow_validator.h"
#include "rac/core/rac_error.h"

namespace {

int g_failed = 0;
int g_passed = 0;

#define CHECK(cond)                                                               \
    do {                                                                          \
        if (!(cond)) {                                                            \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                           \
            return;                                                               \
        }                                                                         \
    } while (0)

#define TEST(name)                                      \
    static void test_##name();                          \
    static void run_test_##name() {                     \
        std::fprintf(stderr, "[RUN ] %s\n", #name);     \
        int before_failed = g_failed;                   \
        test_##name();                                  \
        if (g_failed == before_failed) {                \
            std::fprintf(stderr, "[  OK] %s\n", #name); \
            g_passed++;                                 \
        }                                               \
    }                                                   \
    static void test_##name()

using rac::agent::assemble_bundle;
using rac::agent::ExpressionContext;
using rac::agent::NodePorts;
using rac::agent::pack_recursion_would_occur;
using rac::agent::PackLoader;
using rac::agent::ports_for;
using rac::agent::referenced_node_names;
using rac::agent::resolve_expression;
using rac::agent::topological_order;
using rac::agent::validate_document;
using runanywhere::v1::NodePack;
using runanywhere::v1::WorkflowBundle;
using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowNode;
using runanywhere::v1::WorkflowValidationResult;

WorkflowNode* add_trigger(WorkflowDocument* document, const std::string& id,
                          const std::string& name) {
    WorkflowNode* node = document->add_nodes();
    node->set_id(id);
    node->set_name(name);
    node->mutable_manual_trigger();
    return node;
}

WorkflowNode* add_llm(WorkflowDocument* document, const std::string& id, const std::string& name,
                      const std::string& prompt) {
    WorkflowNode* node = document->add_nodes();
    node->set_id(id);
    node->set_name(name);
    node->mutable_llm_generate()->set_prompt(prompt);
    return node;
}

WorkflowNode* add_condition(WorkflowDocument* document, const std::string& id,
                            const std::string& name) {
    WorkflowNode* node = document->add_nodes();
    node->set_id(id);
    node->set_name(name);
    node->mutable_condition()->set_left("1");
    node->mutable_condition()->set_right("1");
    return node;
}

void connect(WorkflowDocument* document, const std::string& from, const std::string& from_port,
             const std::string& to, const std::string& to_port) {
    auto* edge = document->add_edges();
    edge->set_from_node(from);
    edge->set_from_port(from_port);
    edge->set_to_node(to);
    edge->set_to_port(to_port);
}

bool has_issue_containing(const WorkflowValidationResult& result, const std::string& needle) {
    for (const auto& issue : result.issues()) {
        if (issue.message().find(needle) != std::string::npos)
            return true;
    }
    return false;
}

WorkflowDocument two_node_document() {
    WorkflowDocument document;
    document.set_id("wf");
    document.set_name("Two node");
    add_trigger(&document, "n1", "Start");
    add_llm(&document, "n2", "Summarize", "hello");
    connect(&document, "n1", "out", "n2", "in");
    return document;
}

TEST(minimal_document_is_valid) {
    const WorkflowDocument document = two_node_document();
    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(result.valid());
    CHECK(result.issues_size() == 0);
}

TEST(duplicate_node_id_is_rejected) {
    WorkflowDocument document = two_node_document();
    add_llm(&document, "n2", "Other", "x");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "duplicate node id"));
}

TEST(duplicate_node_name_is_rejected) {
    WorkflowDocument document = two_node_document();
    add_llm(&document, "n3", "Summarize", "x");
    connect(&document, "n2", "out", "n3", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "duplicate node name"));
}

TEST(node_without_config_is_rejected) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* bare = document.add_nodes();
    bare->set_id("n2");
    bare->set_name("Bare");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "no configuration set"));
}

TEST(edge_to_unknown_node_is_rejected) {
    WorkflowDocument document = two_node_document();
    connect(&document, "n2", "out", "missing", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "unknown node"));
}

TEST(edge_on_undeclared_port_is_rejected) {
    WorkflowDocument document = two_node_document();
    // A trigger has no input port, so nothing may arrive at it.
    connect(&document, "n2", "out", "n1", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "no input port"));
}

TEST(condition_declares_true_and_false_ports) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    add_condition(&document, "n2", "Check");
    add_llm(&document, "n3", "Yes", "y");
    add_llm(&document, "n4", "No", "n");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "true", "n3", "in");
    connect(&document, "n2", "false", "n4", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(result.valid());
}

TEST(condition_rejects_an_out_port) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    add_condition(&document, "n2", "Check");
    add_llm(&document, "n3", "Yes", "y");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "out", "n3", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "no output port"));
}

TEST(cycle_is_detected) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    add_llm(&document, "n2", "A", "a");
    add_llm(&document, "n3", "B", "b");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "out", "n3", "in");
    connect(&document, "n3", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "cycle"));
    CHECK(topological_order(document).empty());
}

TEST(missing_trigger_is_rejected) {
    WorkflowDocument document;
    document.set_id("wf");
    add_llm(&document, "n1", "Only", "x");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "no trigger"));
}

TEST(two_triggers_are_rejected) {
    WorkflowDocument document = two_node_document();
    add_trigger(&document, "n3", "Second");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "more than one trigger"));
}

TEST(expression_referencing_unknown_node_is_rejected) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    add_llm(&document, "n2", "Summarize", "value is {{ Nope.field }}");
    connect(&document, "n1", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "unknown node 'Nope'"));
}

TEST(loop_body_must_reference_existing_nodes) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* loop = document.add_nodes();
    loop->set_id("n2");
    loop->set_name("Loop");
    loop->mutable_loop_over_items()->set_items("{{ Start.items }}");
    loop->mutable_loop_over_items()->add_body_node_ids("ghost");
    connect(&document, "n1", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "unknown body node"));
}

TEST(topological_order_follows_edges) {
    WorkflowDocument document;
    document.set_id("wf");
    // Added out of execution order on purpose.
    add_llm(&document, "n3", "Third", "c");
    add_trigger(&document, "n1", "Start");
    add_llm(&document, "n2", "Second", "b");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "out", "n3", "in");

    const std::vector<std::string> order = topological_order(document);
    CHECK(order.size() == 3);
    CHECK(order[0] == "n1");
    CHECK(order[1] == "n2");
    CHECK(order[2] == "n3");
}

TEST(loop_body_nodes_are_excluded_from_the_outer_order) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* loop = document.add_nodes();
    loop->set_id("n2");
    loop->set_name("Loop");
    loop->mutable_loop_over_items()->set_items("{{ Start.items }}");
    loop->mutable_loop_over_items()->add_body_node_ids("n3");
    add_llm(&document, "n3", "Body", "b");
    connect(&document, "n1", "out", "n2", "in");

    const std::vector<std::string> order = topological_order(document);
    CHECK(order.size() == 2);
    CHECK(order[0] == "n1");
    CHECK(order[1] == "n2");
}

TEST(referenced_names_are_extracted) {
    WorkflowNode node;
    node.set_id("n");
    node.set_name("N");
    node.mutable_llm_generate()->set_prompt("{{ A.x }} and {{ B.y.z }}");

    const std::vector<std::string> names = referenced_node_names(node);
    CHECK(names.size() == 2);
    CHECK(names[0] == "A");
    CHECK(names[1] == "B");
}

TEST(expression_with_no_reference_passes_through) {
    ExpressionContext context;
    std::string value;
    std::string error;
    CHECK(resolve_expression("plain text", context, &value, &error));
    CHECK(value == "plain text");
}

TEST(whole_expression_keeps_the_value_type) {
    ExpressionContext context;
    context.node_outputs["A"] = {R"({"count": 42, "nested": {"k": "v"}})"};

    std::string value;
    std::string error;
    CHECK(resolve_expression("{{ A.count }}", context, &value, &error));
    CHECK(value == "42");

    CHECK(resolve_expression("{{ A.nested }}", context, &value, &error));
    CHECK(value.find("\"k\"") != std::string::npos);
}

TEST(interpolated_expression_reads_naturally) {
    ExpressionContext context;
    context.node_outputs["A"] = {R"({"name": "world"})"};

    std::string value;
    std::string error;
    CHECK(resolve_expression("hello {{ A.name }}!", context, &value, &error));
    CHECK(value == "hello world!");
}

TEST(output_and_json_segments_are_optional) {
    ExpressionContext context;
    context.node_outputs["A"] = {R"({"count": 7})"};

    std::string direct;
    std::string via_output;
    std::string via_json;
    std::string error;
    CHECK(resolve_expression("{{ A.count }}", context, &direct, &error));
    CHECK(resolve_expression("{{ A.output.count }}", context, &via_output, &error));
    CHECK(resolve_expression("{{ A.json.count }}", context, &via_json, &error));
    CHECK(direct == "7");
    CHECK(via_output == "7");
    CHECK(via_json == "7");
}

TEST(array_indexing_works) {
    ExpressionContext context;
    context.node_outputs["A"] = {R"({"items": ["a", "b", "c"]})"};

    std::string value;
    std::string error;
    CHECK(resolve_expression("{{ A.items.1 }}", context, &value, &error));
    CHECK(value == "b");
}

TEST(unknown_node_reference_is_an_error) {
    ExpressionContext context;
    std::string value;
    std::string error;
    CHECK(!resolve_expression("{{ Missing.x }}", context, &value, &error));
    CHECK(error.find("Missing") != std::string::npos);
}

TEST(unknown_field_is_an_error_not_an_empty_string) {
    ExpressionContext context;
    context.node_outputs["A"] = {R"({"count": 1})"};

    std::string value;
    std::string error;
    CHECK(!resolve_expression("{{ A.absent }}", context, &value, &error));
    CHECK(error.find("absent") != std::string::npos);
}

TEST(unbalanced_braces_are_an_error) {
    ExpressionContext context;
    std::string value;
    std::string error;
    CHECK(!resolve_expression("{{ A.x", context, &value, &error));
    CHECK(error.find("unbalanced") != std::string::npos);
}

TEST(item_is_only_available_inside_a_loop) {
    ExpressionContext context;
    std::string value;
    std::string error;
    CHECK(!resolve_expression("{{ item.title }}", context, &value, &error));
    CHECK(error.find("loop") != std::string::npos);

    context.has_current_item = true;
    context.current_item_json = R"({"title": "row"})";
    CHECK(resolve_expression("{{ item.title }}", context, &value, &error));
    CHECK(value == "row");
}

TEST(pack_node_ports_come_from_declared_ports_and_outputs) {
    WorkflowNode node;
    node.set_id("n");
    node.set_name("Pack");
    auto* pack_node = node.mutable_pack_node();
    pack_node->set_pack_id("p1");
    auto* port = pack_node->add_ports();
    port->set_name("query");
    port->set_required(true);
    pack_node->add_outputs("result");
    pack_node->add_outputs("logs");

    const NodePorts ports = ports_for(node);
    CHECK(ports.inputs.size() == 2);
    CHECK(ports.inputs[0] == "in");
    CHECK(ports.inputs[1] == "query");
    CHECK(ports.outputs.size() == 2);
    CHECK(ports.outputs[0] == "result");
    CHECK(ports.outputs[1] == "logs");
}

TEST(pack_node_with_no_declared_outputs_gets_a_single_out_port) {
    WorkflowNode node;
    node.set_id("n");
    node.mutable_pack_node()->set_pack_id("p1");

    const NodePorts ports = ports_for(node);
    CHECK(ports.outputs.size() == 1);
    CHECK(ports.outputs[0] == "out");
}

TEST(missing_pack_node_is_an_issue_but_not_invalid) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* pack = document.add_nodes();
    pack->set_id("n2");
    pack->set_name("Pack");
    pack->mutable_pack_node()->set_pack_id("missing-pack");
    pack->mutable_pack_node()->set_missing(true);
    connect(&document, "n1", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(result.valid());
    CHECK(has_issue_containing(result, "not installed"));
}

TEST(required_pack_port_without_wiring_or_literal_is_rejected) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* pack = document.add_nodes();
    pack->set_id("n2");
    pack->set_name("Pack");
    pack->mutable_pack_node()->set_pack_id("p1");
    auto* port = pack->mutable_pack_node()->add_ports();
    port->set_name("query");
    port->set_required(true);
    connect(&document, "n1", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(!result.valid());
    CHECK(has_issue_containing(result, "has no connection and no configured value"));
}

TEST(required_pack_port_satisfied_by_a_literal_is_not_an_issue) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* pack = document.add_nodes();
    pack->set_id("n2");
    pack->set_name("Pack");
    pack->mutable_pack_node()->set_pack_id("p1");
    auto* port = pack->mutable_pack_node()->add_ports();
    port->set_name("query");
    port->set_required(true);
    (*pack->mutable_pack_node()->mutable_arguments())["query"] = "hello";
    connect(&document, "n1", "out", "n2", "in");

    WorkflowValidationResult result;
    validate_document(document, &result);
    CHECK(result.valid());
}

PackLoader loader_over(const std::unordered_map<std::string, NodePack>& packs) {
    return [&packs](const std::string& id, NodePack* out) {
        auto found = packs.find(id);
        if (found == packs.end())
            return RAC_ERROR_NOT_FOUND;
        *out = found->second;
        return RAC_SUCCESS;
    };
}

WorkflowDocument document_with_pack_node(const std::string& pack_id) {
    WorkflowDocument document;
    document.set_id("wf");
    add_trigger(&document, "n1", "Start");
    WorkflowNode* pack_node = document.add_nodes();
    pack_node->set_id("n2");
    pack_node->set_name("Pack");
    pack_node->mutable_pack_node()->set_pack_id(pack_id);
    connect(&document, "n1", "out", "n2", "in");
    return document;
}

TEST(bundle_assembles_packs_referenced_transitively) {
    NodePack pack_b;
    pack_b.set_id("pack-b");
    pack_b.mutable_script()->set_source("return items;");

    NodePack pack_a;
    pack_a.set_id("pack-a");
    auto* graph = pack_a.mutable_composite()->mutable_graph();
    WorkflowNode* trigger = graph->add_nodes();
    trigger->set_id("t1");
    trigger->mutable_manual_trigger();
    WorkflowNode* nested = graph->add_nodes();
    nested->set_id("t2");
    nested->mutable_pack_node()->set_pack_id("pack-b");

    const std::unordered_map<std::string, NodePack> packs = {{"pack-a", pack_a},
                                                             {"pack-b", pack_b}};
    const WorkflowDocument document = document_with_pack_node("pack-a");

    WorkflowBundle bundle;
    std::string error;
    const rac_result_t status = assemble_bundle({document}, loader_over(packs), &bundle, &error);

    CHECK(status == RAC_SUCCESS);
    CHECK(bundle.workflows_size() == 1);
    CHECK(bundle.packs_size() == 2);
    CHECK(bundle.format_version() == 1);
}

TEST(bundle_assembly_skips_a_pack_it_cannot_load) {
    const std::unordered_map<std::string, NodePack> packs;  // empty: nothing resolves
    const WorkflowDocument document = document_with_pack_node("ghost-pack");

    WorkflowBundle bundle;
    std::string error;
    const rac_result_t status = assemble_bundle({document}, loader_over(packs), &bundle, &error);

    CHECK(status == RAC_SUCCESS);
    CHECK(bundle.workflows_size() == 1);
    CHECK(bundle.packs_size() == 0);
}

TEST(bundle_assembly_rejects_a_pack_cycle) {
    NodePack pack_a;
    pack_a.set_id("pack-a");
    auto* graph_a = pack_a.mutable_composite()->mutable_graph();
    WorkflowNode* trigger_a = graph_a->add_nodes();
    trigger_a->set_id("t1");
    trigger_a->mutable_manual_trigger();
    WorkflowNode* ref_b = graph_a->add_nodes();
    ref_b->set_id("t2");
    ref_b->mutable_pack_node()->set_pack_id("pack-b");

    NodePack pack_b;
    pack_b.set_id("pack-b");
    auto* graph_b = pack_b.mutable_composite()->mutable_graph();
    WorkflowNode* trigger_b = graph_b->add_nodes();
    trigger_b->set_id("u1");
    trigger_b->mutable_manual_trigger();
    WorkflowNode* ref_a = graph_b->add_nodes();
    ref_a->set_id("u2");
    ref_a->mutable_pack_node()->set_pack_id("pack-a");

    const std::unordered_map<std::string, NodePack> packs = {{"pack-a", pack_a},
                                                             {"pack-b", pack_b}};
    const WorkflowDocument document = document_with_pack_node("pack-a");

    WorkflowBundle bundle;
    std::string error;
    const rac_result_t status = assemble_bundle({document}, loader_over(packs), &bundle, &error);

    CHECK(status != RAC_SUCCESS);
    CHECK(error.find("cyclic") != std::string::npos);
}

TEST(pack_recursion_guard_detects_self_reference_on_the_stack) {
    const std::vector<std::string> stack = {"pack-a", "pack-b"};
    CHECK(pack_recursion_would_occur(stack, "pack-a"));
    CHECK(!pack_recursion_would_occur(stack, "pack-c"));
}

TEST(pack_recursion_guard_enforces_a_depth_ceiling) {
    const std::vector<std::string> stack(rac::agent::kMaxPackDepth, "x");
    CHECK(pack_recursion_would_occur(stack, "a-pack-not-on-the-stack"));
}

}  // namespace

int main() {
    run_test_minimal_document_is_valid();
    run_test_duplicate_node_id_is_rejected();
    run_test_duplicate_node_name_is_rejected();
    run_test_node_without_config_is_rejected();
    run_test_edge_to_unknown_node_is_rejected();
    run_test_edge_on_undeclared_port_is_rejected();
    run_test_condition_declares_true_and_false_ports();
    run_test_condition_rejects_an_out_port();
    run_test_cycle_is_detected();
    run_test_missing_trigger_is_rejected();
    run_test_two_triggers_are_rejected();
    run_test_expression_referencing_unknown_node_is_rejected();
    run_test_loop_body_must_reference_existing_nodes();
    run_test_topological_order_follows_edges();
    run_test_loop_body_nodes_are_excluded_from_the_outer_order();
    run_test_referenced_names_are_extracted();
    run_test_expression_with_no_reference_passes_through();
    run_test_whole_expression_keeps_the_value_type();
    run_test_interpolated_expression_reads_naturally();
    run_test_output_and_json_segments_are_optional();
    run_test_array_indexing_works();
    run_test_unknown_node_reference_is_an_error();
    run_test_unknown_field_is_an_error_not_an_empty_string();
    run_test_unbalanced_braces_are_an_error();
    run_test_item_is_only_available_inside_a_loop();
    run_test_pack_node_ports_come_from_declared_ports_and_outputs();
    run_test_pack_node_with_no_declared_outputs_gets_a_single_out_port();
    run_test_missing_pack_node_is_an_issue_but_not_invalid();
    run_test_required_pack_port_without_wiring_or_literal_is_rejected();
    run_test_required_pack_port_satisfied_by_a_literal_is_not_an_issue();
    run_test_bundle_assembles_packs_referenced_transitively();
    run_test_bundle_assembly_skips_a_pack_it_cannot_load();
    run_test_bundle_assembly_rejects_a_pack_cycle();
    run_test_pack_recursion_guard_detects_self_reference_on_the_stack();
    run_test_pack_recursion_guard_enforces_a_depth_ceiling();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
