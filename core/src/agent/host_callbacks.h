// SPDX-License-Identifier: Apache-2.0
//
// Storage for the host-supplied implementations of the two node types commons
// cannot run on its own: Tool Call needs the host's tool registry, and Code
// needs a JavaScript engine.

#pragma once

#include "rac/agent/rac_agent_workflow.h"

namespace rac::agent {

rac_result_t set_host_callbacks(const rac_agent_host_callbacks_t* callbacks);

/// Snapshot of the current table. Copied by value so a run in flight cannot
/// observe a half-replaced struct.
rac_agent_host_callbacks_t host_callbacks();

}  // namespace rac::agent
