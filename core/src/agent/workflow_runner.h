// SPDX-License-Identifier: Apache-2.0
//
// Walks a validated workflow once, in topological order, emitting a state
// change per node.
//
// One run, one background thread. Nodes execute sequentially rather than
// concurrently: a workflow step is a slow LLM call or an HTTP round trip that
// the user wants to watch, so ordering the user can follow is worth more than
// overlapping two steps.

#pragma once

#include "agent_workflow.pb.h"
#include "expression.h"
#include "node_executors.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "rac/agent/rac_agent_workflow.h"
#include "rac/core/rac_error.h"

namespace rac::agent {

class WorkflowRunner {
   public:
    WorkflowRunner(runanywhere::v1::WorkflowDocument document, std::string run_id,
                   std::vector<runanywhere::v1::WorkflowItem> initial_items,
                   rac_agent_run_event_callback_fn event_callback, void* user_data);
    ~WorkflowRunner();

    WorkflowRunner(const WorkflowRunner&) = delete;
    WorkflowRunner& operator=(const WorkflowRunner&) = delete;

    rac_result_t start();

    /// Non-blocking. The running node finishes, nothing further is scheduled,
    /// and the record closes as cancelled.
    void cancel();

    void join();

    /// Safe at any point in the lifecycle, including mid-run.
    runanywhere::v1::WorkflowRunRecord record() const;

   private:
    void run();
    void execute_one(const runanywhere::v1::WorkflowNode& node);
    void execute_loop(const runanywhere::v1::WorkflowNode& node,
                      const std::vector<runanywhere::v1::WorkflowItem>& inputs);

    NodeInputs gather_inputs(const std::string& node_id) const;

    /// True when every incoming edge arrives from a node that was skipped or
    /// never ran, which is how a Condition's untaken branch propagates.
    bool upstream_is_dead(const std::string& node_id) const;

    void set_state(const std::string& node_id, runanywhere::v1::NodeRunState state,
                   const std::vector<runanywhere::v1::WorkflowItem>& output,
                   const std::string& error_message);

    void emit(const runanywhere::v1::WorkflowRunEvent& event) const;

    runanywhere::v1::WorkflowDocument document_;
    std::string run_id_;
    std::vector<runanywhere::v1::WorkflowItem> initial_items_;

    rac_agent_run_event_callback_fn event_callback_;
    void* user_data_;

    mutable std::mutex mutex_;
    runanywhere::v1::WorkflowRunRecord record_;
    std::unordered_map<std::string, runanywhere::v1::NodeRunState> states_;

    /// Items keyed by node, then by the output port they left on. Per-port
    /// storage is what lets Filter feed its "true" and "false" edges different
    /// items from a single execution.
    std::unordered_map<std::string,
                       std::unordered_map<std::string, std::vector<runanywhere::v1::WorkflowItem>>>
        outputs_;

    /// Port a Condition emitted on, so edges leaving the other port know their
    /// target is dead.
    std::unordered_map<std::string, std::string> taken_ports_;

    ExpressionContext context_;

    std::atomic<bool> cancelled_{false};
    std::thread thread_;
    bool started_ = false;
    bool joined_ = false;
};

}  // namespace rac::agent
