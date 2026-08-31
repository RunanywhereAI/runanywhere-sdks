// SPDX-License-Identifier: Apache-2.0
//
// One function per node type, each taking the items its parents produced and
// returning the items it emits.
//
// Executors know nothing about scheduling, ordering, or persistence. Loop Over
// Items is the exception and lives in the runner, because iterating a body
// means re-entering the scheduler.

#pragma once

#include "agent_workflow.pb.h"
#include "expression.h"

#include <atomic>
#include <map>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"

namespace rac::agent {

struct NodeInputs {
    /// Every incoming item, in edge order. What most executors consume.
    std::vector<runanywhere::v1::WorkflowItem> items;

    /// The same items keyed by the input port they arrived on, for the nodes
    /// whose ports carry meaning: Merge's numbered branches and Tool Call's
    /// per-argument ports.
    std::map<std::string, std::vector<runanywhere::v1::WorkflowItem>> by_port;
};

struct NodeExecution {
    std::vector<runanywhere::v1::WorkflowItem> items;

    /// Which output port the items leave on. Condition and Filter set "true";
    /// everything else emits on "out".
    std::string port = "out";

    /// Filter is the one node that emits on two ports in a single execution:
    /// `items` carries the kept side and this carries the rest.
    std::vector<runanywhere::v1::WorkflowItem> secondary_items;
    std::string secondary_port;
};

/// Ceiling on composite pack nesting: entering a subgraph pushes the pack id
/// onto the run's pack stack, so a cycle through several packs is caught, not
/// just a pack that references itself directly.
inline constexpr size_t kMaxPackDepth = 64;

/// True when executing @p pack_id would recurse: it is already being
/// expanded somewhere up the current call chain, or the chain has already
/// reached the nesting ceiling. Exposed standalone so the guard is testable
/// without a platform adapter.
bool pack_recursion_would_occur(const std::vector<std::string>& pack_stack,
                                const std::string& pack_id);

/// Execute @p node against @p inputs.
///
/// @p cancelled may be null; when set, long-running executors (Wait, a
/// composite pack's subgraph) observe it and return early instead of
/// blocking a cancel for their full duration.
///
/// @p pack_stack tracks which packs are currently being expanded, so a
/// composite pack node can detect recursing back into itself. Null at the
/// top of a call chain; execute_node allocates its own when a pack node
/// needs one.
///
/// Returns RAC_SUCCESS on success. On failure @p out_error carries a message
/// meant for the canvas, not a log line.
rac_result_t execute_node(const runanywhere::v1::WorkflowNode& node, const NodeInputs& inputs,
                          const ExpressionContext& context, const std::string& run_id,
                          const std::atomic<bool>* cancelled, NodeExecution* out_execution,
                          std::string* out_error, std::vector<std::string>* pack_stack = nullptr);

}  // namespace rac::agent
