// SPDX-License-Identifier: Apache-2.0
//
// Static checks a workflow must pass before it can be stored or run.
//
// Validation never throws and never returns a failure for an invalid document:
// the verdict is data, so the canvas can render every problem at once instead
// of surfacing them one exception at a time.

#pragma once

#include "agent_workflow.pb.h"

#include <string>
#include <vector>

namespace rac::agent {

/// Ports a node type accepts, keyed by the oneof arm that is set.
struct NodePorts {
    std::vector<std::string> inputs;
    std::vector<std::string> outputs;
};

NodePorts ports_for(const runanywhere::v1::WorkflowNode& node);

/// True when the node's config oneof is set to a known arm.
bool node_has_config(const runanywhere::v1::WorkflowNode& node);

/// True for any node that starts a run rather than being reached by an edge.
bool is_trigger(const runanywhere::v1::WorkflowNode& node);

void validate_document(const runanywhere::v1::WorkflowDocument& document,
                       runanywhere::v1::WorkflowValidationResult* out_result);

/// Node ids in execution order. Empty when the graph contains a cycle, which
/// validate_document reports separately. Loop body nodes are excluded because
/// their loop owns their scheduling.
std::vector<std::string> topological_order(const runanywhere::v1::WorkflowDocument& document);

/// Node names referenced by `{{ Name.path }}` anywhere in a node's config.
std::vector<std::string> referenced_node_names(const runanywhere::v1::WorkflowNode& node);

}  // namespace rac::agent
