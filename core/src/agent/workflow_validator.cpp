// SPDX-License-Identifier: Apache-2.0

#include "workflow_validator.h"

#include "cron.h"

#include <algorithm>
#include <deque>
#include <optional>
#include <set>
#include <string>
#include <unordered_map>
#include <unordered_set>

namespace rac::agent {
namespace {

using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowNode;

/// Reserved head of an expression, bound to the element under evaluation rather
/// than to any node. Must match the name `expression.cpp` resolves.
constexpr const char* kCurrentItemBinding = "item";

constexpr const char* kPortIn = "in";
constexpr const char* kPortOut = "out";
constexpr const char* kPortTrue = "true";
constexpr const char* kPortFalse = "false";

void add_issue(runanywhere::v1::WorkflowValidationResult* result, const std::string& message,
               const std::string* node_id = nullptr, const std::string* edge_from = nullptr) {
    runanywhere::v1::WorkflowValidationIssue* issue = result->add_issues();
    issue->set_message(message);
    if (node_id != nullptr)
        issue->set_node_id(*node_id);
    if (edge_from != nullptr)
        issue->set_edge_from(*edge_from);
}

void collect_expressions(const WorkflowNode& node, std::vector<std::string>* out) {
    switch (node.config_case()) {
        case WorkflowNode::kManualTrigger:
            out->push_back(node.manual_trigger().initial_items_json());
            break;
        case WorkflowNode::kToolCall:
            for (const auto& [name, value] : node.tool_call().arguments())
                out->push_back(value);
            break;
        case WorkflowNode::kLlmGenerate:
            out->push_back(node.llm_generate().prompt());
            if (node.llm_generate().has_system_prompt())
                out->push_back(node.llm_generate().system_prompt());
            break;
        case WorkflowNode::kCondition:
            out->push_back(node.condition().left());
            out->push_back(node.condition().right());
            break;
        case WorkflowNode::kLoopOverItems:
            out->push_back(node.loop_over_items().items());
            break;
        case WorkflowNode::kCode:
            break;
        case WorkflowNode::kHttpRequest:
            out->push_back(node.http_request().url());
            for (const auto& [name, value] : node.http_request().headers())
                out->push_back(value);
            if (node.http_request().has_body())
                out->push_back(node.http_request().body());
            break;
        case WorkflowNode::kSetTransform:
            for (const auto& assignment : node.set_transform().assignments())
                out->push_back(assignment.value());
            break;
        case WorkflowNode::kScheduleTrigger:
            out->push_back(node.schedule_trigger().initial_items_json());
            break;
        case WorkflowNode::kFilter:
            out->push_back(node.filter().left());
            out->push_back(node.filter().right());
            break;
        case WorkflowNode::kSplitOut:
            out->push_back(node.split_out().field());
            break;
        case WorkflowNode::kAggregate:
            out->push_back(node.aggregate().field());
            break;
        case WorkflowNode::kFileRead:
            out->push_back(node.file_read().path());
            break;
        case WorkflowNode::kFileWrite:
            out->push_back(node.file_write().path());
            out->push_back(node.file_write().content());
            break;
        case WorkflowNode::kLlmStructured:
            out->push_back(node.llm_structured().prompt());
            if (node.llm_structured().has_system_prompt())
                out->push_back(node.llm_structured().system_prompt());
            break;
        case WorkflowNode::kVision:
            out->push_back(node.vision().prompt());
            break;
        case WorkflowNode::kEmbed:
            out->push_back(node.embed().text());
            break;
        case WorkflowNode::kRerank:
            out->push_back(node.rerank().query());
            out->push_back(node.rerank().documents());
            break;
        case WorkflowNode::kSpeak:
            out->push_back(node.speak().text());
            break;
        case WorkflowNode::kSegment:
            out->push_back(node.segment().text());
            break;
        case WorkflowNode::kRagQuery:
            out->push_back(node.rag_query().question());
            break;
        case WorkflowNode::kRagIngest:
            out->push_back(node.rag_ingest().text());
            break;
        case WorkflowNode::kPackNode:
            for (const auto& [name, value] : node.pack_node().arguments())
                out->push_back(value);
            break;
        case WorkflowNode::kMerge:
        case WorkflowNode::kWait:
        case WorkflowNode::kTranscribe:
        case WorkflowNode::kDetectVoice:
        case WorkflowNode::kDiarize:
        case WorkflowNode::kLoadModel:
        case WorkflowNode::CONFIG_NOT_SET:
            break;
    }
}

}  // namespace

bool node_has_config(const WorkflowNode& node) {
    return node.config_case() != WorkflowNode::CONFIG_NOT_SET;
}

NodePorts ports_for(const WorkflowNode& node) {
    switch (node.config_case()) {
        case WorkflowNode::kManualTrigger:
        case WorkflowNode::kScheduleTrigger:
            return {{}, {kPortOut}};

        case WorkflowNode::kCondition:
        case WorkflowNode::kFilter:
            return {{kPortIn}, {kPortTrue, kPortFalse}};

        case WorkflowNode::kToolCall: {
            // A tool node's inputs are its arguments. The port list travels in
            // the document, so this stays correct on a machine where the tool
            // itself is not installed. `in` remains so a tool can also be
            // chained without wiring every argument.
            NodePorts ports{{kPortIn}, {kPortOut}};
            for (const auto& argument : node.tool_call().ports())
                ports.inputs.push_back(argument.name());
            return ports;
        }

        case WorkflowNode::kMerge: {
            // Numbered inputs, because a fan-in needs to keep its branches
            // apart to concatenate them in a defined order.
            NodePorts ports{{}, {kPortOut}};
            const uint32_t count = node.merge().input_count() > 0 ? node.merge().input_count() : 2;
            for (uint32_t index = 0; index < count; ++index)
                ports.inputs.push_back("in" + std::to_string(index + 1));
            return ports;
        }

        case WorkflowNode::kPackNode: {
            // Same shape as kToolCall for inputs: `in` plus one declared port
            // per pack argument. Outputs are mirrored at drop time too,
            // defaulting to the single `out` every other node type has.
            NodePorts ports{{kPortIn}, {}};
            for (const auto& port : node.pack_node().ports())
                ports.inputs.push_back(port.name());
            if (node.pack_node().outputs_size() == 0) {
                ports.outputs.push_back(kPortOut);
            } else {
                for (const auto& output : node.pack_node().outputs())
                    ports.outputs.push_back(output);
            }
            return ports;
        }

        case WorkflowNode::kLlmGenerate:
        case WorkflowNode::kLoopOverItems:
        case WorkflowNode::kCode:
        case WorkflowNode::kHttpRequest:
        case WorkflowNode::kSetTransform:
        case WorkflowNode::kSplitOut:
        case WorkflowNode::kAggregate:
        case WorkflowNode::kWait:
        case WorkflowNode::kFileRead:
        case WorkflowNode::kFileWrite:
        case WorkflowNode::kLlmStructured:
        case WorkflowNode::kVision:
        case WorkflowNode::kEmbed:
        case WorkflowNode::kRerank:
        case WorkflowNode::kTranscribe:
        case WorkflowNode::kSpeak:
        case WorkflowNode::kDetectVoice:
        case WorkflowNode::kDiarize:
        case WorkflowNode::kSegment:
        case WorkflowNode::kRagQuery:
        case WorkflowNode::kRagIngest:
        case WorkflowNode::kLoadModel:
            return {{kPortIn}, {kPortOut}};

        case WorkflowNode::CONFIG_NOT_SET:
            return {};
    }
    return {};
}

bool is_trigger(const WorkflowNode& node) {
    return node.config_case() == WorkflowNode::kManualTrigger ||
           node.config_case() == WorkflowNode::kScheduleTrigger;
}

std::vector<std::string> referenced_node_names(const WorkflowNode& node) {
    std::vector<std::string> expressions;
    collect_expressions(node, &expressions);

    std::vector<std::string> names;
    for (const std::string& expression : expressions) {
        size_t cursor = 0;
        while ((cursor = expression.find("{{", cursor)) != std::string::npos) {
            const size_t close = expression.find("}}", cursor + 2);
            if (close == std::string::npos)
                break;

            std::string body = expression.substr(cursor + 2, close - cursor - 2);
            cursor = close + 2;

            const size_t first = body.find_first_not_of(" \t");
            if (first == std::string::npos)
                continue;
            const size_t last = body.find_last_not_of(" \t");
            body = body.substr(first, last - first + 1);

            // `Name.path.to.field` — the node name is everything before the
            // first dot, so a name containing a dot is not addressable. The
            // canvas assigns names, so that is a naming constraint, not a bug.
            const size_t dot = body.find('.');
            std::string head = dot == std::string::npos ? body : body.substr(0, dot);

            // `item` is the current element bound by Loop Over Items and by
            // Filter's per-item evaluation, not a node. Reporting it as an
            // unknown node made every Filter unsaveable.
            if (head == kCurrentItemBinding)
                continue;

            names.push_back(std::move(head));
        }
    }
    return names;
}

std::vector<std::string> topological_order(const WorkflowDocument& document) {
    std::unordered_set<std::string> loop_owned;
    for (const WorkflowNode& node : document.nodes()) {
        if (node.config_case() != WorkflowNode::kLoopOverItems)
            continue;
        for (const std::string& id : node.loop_over_items().body_node_ids())
            loop_owned.insert(id);
    }

    std::unordered_map<std::string, int> indegree;
    std::unordered_map<std::string, std::vector<std::string>> successors;
    for (const WorkflowNode& node : document.nodes()) {
        if (loop_owned.count(node.id()) == 0)
            indegree[node.id()] = 0;
    }

    for (const auto& edge : document.edges()) {
        if (indegree.count(edge.from_node()) == 0 || indegree.count(edge.to_node()) == 0)
            continue;
        successors[edge.from_node()].push_back(edge.to_node());
        indegree[edge.to_node()] += 1;
    }

    // Seed in document order so an unconnected graph still runs its nodes in
    // the order the user placed them, which keeps runs reproducible.
    std::deque<std::string> ready;
    for (const WorkflowNode& node : document.nodes()) {
        if (loop_owned.count(node.id()) == 0 && indegree[node.id()] == 0)
            ready.push_back(node.id());
    }

    std::vector<std::string> order;
    while (!ready.empty()) {
        const std::string current = ready.front();
        ready.pop_front();
        order.push_back(current);

        auto it = successors.find(current);
        if (it == successors.end())
            continue;
        for (const std::string& next : it->second) {
            if (--indegree[next] == 0)
                ready.push_back(next);
        }
    }

    if (order.size() != indegree.size())
        return {};
    return order;
}

void validate_document(const WorkflowDocument& document,
                       runanywhere::v1::WorkflowValidationResult* out_result) {
    out_result->Clear();

    std::unordered_map<std::string, const WorkflowNode*> by_id;
    std::unordered_set<std::string> names;
    int trigger_count = 0;

    for (const WorkflowNode& node : document.nodes()) {
        if (node.id().empty()) {
            add_issue(out_result, "node has an empty id");
            continue;
        }
        if (!by_id.emplace(node.id(), &node).second) {
            const std::string& id = node.id();
            add_issue(out_result, "duplicate node id '" + id + "'", &id);
            continue;
        }
        if (!node_has_config(node)) {
            const std::string& id = node.id();
            add_issue(out_result, "node '" + id + "' has no configuration set", &id);
        }
        // Expressions address nodes by name, so two nodes sharing one makes the
        // reference ambiguous rather than merely confusing.
        if (!node.name().empty() && !names.insert(node.name()).second) {
            const std::string& id = node.id();
            add_issue(out_result, "duplicate node name '" + node.name() + "'", &id);
        }
        if (is_trigger(node))
            trigger_count += 1;
    }

    if (document.nodes_size() > 0 && trigger_count == 0)
        add_issue(out_result, "workflow has no trigger node");
    if (trigger_count > 1)
        add_issue(out_result, "workflow has more than one trigger node");

    std::set<std::string> seen_edges;
    for (const auto& edge : document.edges()) {
        const std::string& from = edge.from_node();
        const std::string signature =
            from + ":" + edge.from_port() + "->" + edge.to_node() + ":" + edge.to_port();
        if (!seen_edges.insert(signature).second) {
            add_issue(out_result, "duplicate edge " + signature, nullptr, &from);
            continue;
        }

        auto from_it = by_id.find(edge.from_node());
        auto to_it = by_id.find(edge.to_node());
        if (from_it == by_id.end()) {
            add_issue(out_result, "edge starts at unknown node '" + from + "'", nullptr, &from);
            continue;
        }
        if (to_it == by_id.end()) {
            add_issue(out_result, "edge ends at unknown node '" + edge.to_node() + "'", nullptr,
                      &from);
            continue;
        }

        const NodePorts from_ports = ports_for(*from_it->second);
        const NodePorts to_ports = ports_for(*to_it->second);
        if (std::find(from_ports.outputs.begin(), from_ports.outputs.end(), edge.from_port()) ==
            from_ports.outputs.end()) {
            add_issue(out_result,
                      "node '" + from + "' has no output port '" + edge.from_port() + "'", nullptr,
                      &from);
        }
        if (std::find(to_ports.inputs.begin(), to_ports.inputs.end(), edge.to_port()) ==
            to_ports.inputs.end()) {
            const std::string& to = edge.to_node();
            add_issue(out_result, "node '" + to + "' has no input port '" + edge.to_port() + "'",
                      &to);
        }
    }

    for (const WorkflowNode& node : document.nodes()) {
        if (node.config_case() != WorkflowNode::kLoopOverItems)
            continue;
        for (const std::string& body_id : node.loop_over_items().body_node_ids()) {
            if (by_id.count(body_id) == 0) {
                const std::string& id = node.id();
                add_issue(out_result,
                          "loop '" + id + "' references unknown body node '" + body_id + "'", &id);
            }
        }
    }

    for (const WorkflowNode& node : document.nodes()) {
        for (const std::string& referenced : referenced_node_names(node)) {
            if (names.count(referenced) == 0) {
                const std::string& id = node.id();
                add_issue(out_result, "expression references unknown node '" + referenced + "'",
                          &id);
            }
        }
    }

    for (const WorkflowNode& node : document.nodes()) {
        if (node.config_case() != WorkflowNode::kPackNode)
            continue;
        const auto& config = node.pack_node();
        for (const auto& port : config.ports()) {
            if (!port.required())
                continue;
            const bool wired = std::any_of(
                document.edges().begin(), document.edges().end(), [&](const auto& edge) {
                    return edge.to_node() == node.id() && edge.to_port() == port.name();
                });
            if (wired || config.arguments().count(port.name()) > 0)
                continue;
            const std::string& id = node.id();
            add_issue(out_result,
                      "pack argument '" + port.name() + "' on node '" + id +
                          "' has no connection and no configured value",
                      &id);
        }
    }

    for (const WorkflowNode& node : document.nodes()) {
        if (node.config_case() != WorkflowNode::kScheduleTrigger)
            continue;
        const auto& schedule = node.schedule_trigger();
        if (schedule.kind() != runanywhere::v1::SCHEDULE_KIND_CRON)
            continue;

        const std::string& id = node.id();
        if (schedule.cron().empty()) {
            add_issue(out_result, "cron schedule on node '" + id + "' has no expression", &id);
            continue;
        }

        std::string error;
        const std::optional<CronExpression> parsed = CronExpression::parse(schedule.cron(), &error);
        if (!parsed.has_value()) {
            add_issue(out_result,
                      "cron expression '" + schedule.cron() + "' on node '" + id +
                          "' is invalid: " + error,
                      &id);
        } else if (!parsed->ever_fires()) {
            add_issue(out_result,
                      "cron expression '" + schedule.cron() + "' on node '" + id + "' never fires",
                      &id);
        }
    }

    if (document.nodes_size() > 0 && topological_order(document).empty())
        add_issue(out_result, "workflow contains a cycle");

    out_result->set_valid(out_result->issues_size() == 0);

    // A pack the machine does not have is visible in the issue list, but not
    // a reason to refuse the document: the same reasoning ToolCallConfig uses
    // for a tool the host registry no longer has. Added after `valid` is
    // computed so it never flips a document that is otherwise fine.
    for (const WorkflowNode& node : document.nodes()) {
        if (node.config_case() == WorkflowNode::kPackNode && node.pack_node().missing()) {
            const std::string& id = node.id();
            add_issue(out_result, "pack '" + node.pack_node().pack_id() + "' is not installed",
                      &id);
        }
    }
}

}  // namespace rac::agent
