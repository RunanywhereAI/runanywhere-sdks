// SPDX-License-Identifier: Apache-2.0
//
// pipeline_executor.cpp — T4.7 spec compiler.

#include "rac/solutions/pipeline_executor.hpp"

#include <algorithm>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#include "rac/core/rac_error.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/graph/pipeline_node.hpp"

namespace rac::solutions {

namespace {

void set_detail(const std::string& msg) {
    rac_error_set_details(msg.c_str());
}

/// Split an "operator.port" endpoint. We accept bare "operator" too —
/// the port is advisory at the string level since every operator has
/// a single input/output edge in the current executor contract.
std::string split_endpoint_operator(const std::string& endpoint) {
    auto dot = endpoint.find('.');
    if (dot == std::string::npos) return endpoint;
    return endpoint.substr(0, dot);
}

}  // namespace

PipelineExecutor::PipelineExecutor(runanywhere::v1::PipelineSpec spec)
    : spec_(std::move(spec)) {}

std::unique_ptr<rac::graph::GraphScheduler>
PipelineExecutor::build(rac_result_t* out_error) {
    rac_result_t status = RAC_SUCCESS;
    auto set_error = [&](rac_result_t code, const std::string& msg) {
        status = code;
        set_detail(msg);
    };
    auto emit_null = [&](rac_result_t code, const std::string& msg)
        -> std::unique_ptr<rac::graph::GraphScheduler> {
        set_error(code, msg);
        if (out_error) *out_error = status;
        return nullptr;
    };

    // ---- 1. Validate operator uniqueness + factory availability -----------
    std::unordered_map<std::string, std::shared_ptr<OperatorNode>> nodes;
    nodes.reserve(spec_.operators_size());

    const auto& registry = OperatorRegistry::instance();
    for (const auto& op : spec_.operators()) {
        if (op.name().empty()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "operator with empty name in spec '" + spec_.name() + "'");
        }
        if (nodes.count(op.name())) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "duplicate operator name: " + op.name());
        }
        if (!registry.has_factory(op.type())) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "no factory registered for operator type '" +
                                 op.type() + "' (operator '" + op.name() + "')");
        }
        auto node = registry.create(op);
        if (!node) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "factory returned null for operator '" + op.name() + "'");
        }
        nodes.emplace(op.name(), std::move(node));
    }

    // ---- 2. Resolve edges + wire the graph --------------------------------
    //
    // Track per-operator in/out degree so we can identify the root
    // input (the operator with zero inbound edges) and root output
    // (the operator with zero outbound edges). The first candidate
    // wins — pipelines with multiple sources/sinks are valid and the
    // caller uses the PipelineSpec itself to steer the extras (e.g.
    // via operator-specific params).
    std::unordered_map<std::string, int> in_degree;
    std::unordered_map<std::string, int> out_degree;
    for (const auto& [name, _] : nodes) {
        in_degree[name]  = 0;
        out_degree[name] = 0;
    }

    auto scheduler = std::make_unique<rac::graph::GraphScheduler>(/*pool*/ 0);
    for (const auto& [_, node] : nodes) {
        scheduler->add_node(node);
    }

    for (const auto& edge : spec_.edges()) {
        const std::string from_op = split_endpoint_operator(edge.from());
        const std::string to_op   = split_endpoint_operator(edge.to());
        auto src = nodes.find(from_op);
        auto dst = nodes.find(to_op);
        if (src == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown producer: " + edge.from());
        }
        if (dst == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown consumer: " + edge.to());
        }
        // Share the producer's output edge with the consumer's input
        // edge. This is the same trick GraphScheduler::connect() uses
        // to get backpressure for free.
        dst->second->set_input(src->second->output());
        ++out_degree[from_op];
        ++in_degree[to_op];
    }

    // ---- 3. Pick root input / root output ---------------------------------
    std::shared_ptr<OperatorNode> root_input_node;
    std::shared_ptr<OperatorNode> root_output_node;
    for (const auto& op : spec_.operators()) {
        auto it = nodes.find(op.name());
        if (it == nodes.end()) continue;
        if (in_degree[op.name()] == 0 && !root_input_node) {
            root_input_node = it->second;
        }
        if (out_degree[op.name()] == 0 && !root_output_node) {
            root_output_node = it->second;
        }
    }

    // ---- 4. Strict validation: no orphaned / unreferenced operators -------
    if (spec_.options().strict_validation()) {
        for (const auto& op : spec_.operators()) {
            const bool is_source = in_degree[op.name()]  == 0;
            const bool is_sink   = out_degree[op.name()] == 0;
            if (is_source && is_sink && spec_.operators_size() > 1) {
                return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                                 "strict_validation: operator '" + op.name() +
                                     "' has no inbound or outbound edges");
            }
        }
    }

    if (root_input_node)  root_input_edge_  = root_input_node->input();
    if (root_output_node) root_output_edge_ = root_output_node->output();

    if (out_error) *out_error = RAC_SUCCESS;
    return scheduler;
}

}  // namespace rac::solutions
