// SPDX-License-Identifier: Apache-2.0

#include "workflow_runner.h"

#include "node_executors.h"
#include "workflow_store.h"
#include "workflow_validator.h"

#include <algorithm>
#include <chrono>
#include <nlohmann/json.hpp>

#include "rac/core/rac_logger.h"

namespace rac::agent {
namespace {

using runanywhere::v1::NodeRunState;
using runanywhere::v1::WorkflowItem;
using runanywhere::v1::WorkflowNode;
using runanywhere::v1::WorkflowRunState;

constexpr const char* kLogCategory = "AgentWorkflow";
constexpr uint32_t kDefaultLoopCeiling = 1000u;

int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

bool is_dead(NodeRunState state) {
    return state == NodeRunState::NODE_RUN_STATE_SKIPPED ||
           state == NodeRunState::NODE_RUN_STATE_FAILED;
}

}  // namespace

WorkflowRunner::WorkflowRunner(runanywhere::v1::WorkflowDocument document, std::string run_id,
                               std::vector<WorkflowItem> initial_items,
                               rac_agent_run_event_callback_fn event_callback, void* user_data)
    : document_(std::move(document)),
      run_id_(std::move(run_id)),
      initial_items_(std::move(initial_items)),
      event_callback_(event_callback),
      user_data_(user_data) {
    record_.set_run_id(run_id_);
    record_.set_workflow_id(document_.id());
    record_.set_state(WorkflowRunState::WORKFLOW_RUN_STATE_UNSPECIFIED);

    for (const WorkflowNode& node : document_.nodes())
        states_[node.id()] = NodeRunState::NODE_RUN_STATE_PENDING;
}

WorkflowRunner::~WorkflowRunner() {
    cancel();
    join();
}

rac_result_t WorkflowRunner::start() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (started_)
        return RAC_ERROR_ALREADY_INITIALIZED;

    started_ = true;
    record_.set_state(WorkflowRunState::WORKFLOW_RUN_STATE_RUNNING);
    record_.set_started_at_ms(now_ms());

    thread_ = std::thread([this] { run(); });
    return RAC_SUCCESS;
}

void WorkflowRunner::cancel() {
    cancelled_.store(true, std::memory_order_relaxed);
}

void WorkflowRunner::join() {
    if (thread_.joinable())
        thread_.join();
    joined_ = true;
}

runanywhere::v1::WorkflowRunRecord WorkflowRunner::record() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return record_;
}

void WorkflowRunner::emit(const runanywhere::v1::WorkflowRunEvent& event) const {
    if (event_callback_ == nullptr)
        return;
    const std::string encoded = event.SerializeAsString();
    event_callback_(reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size(), user_data_);
}

void WorkflowRunner::set_state(const std::string& node_id, NodeRunState state,
                               const std::vector<WorkflowItem>& output,
                               const std::string& error_message) {
    runanywhere::v1::WorkflowRunEvent event;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        states_[node_id] = state;

        runanywhere::v1::NodeRun* entry = nullptr;
        for (runanywhere::v1::NodeRun& candidate : *record_.mutable_node_runs()) {
            if (candidate.node_id() == node_id) {
                entry = &candidate;
                break;
            }
        }
        if (entry == nullptr) {
            entry = record_.add_node_runs();
            entry->set_node_id(node_id);
            entry->set_started_at_ms(now_ms());
        }

        entry->set_state(state);
        if (state != NodeRunState::NODE_RUN_STATE_RUNNING)
            entry->set_finished_at_ms(now_ms());

        entry->clear_output();
        for (const WorkflowItem& item : output)
            *entry->add_output() = item;

        if (!error_message.empty())
            entry->mutable_error()->set_message(error_message);

        event.set_run_id(run_id_);
        runanywhere::v1::NodeStateChanged* changed = event.mutable_node_state_changed();
        changed->set_node_id(node_id);
        changed->set_state(state);
        for (const WorkflowItem& item : output)
            *changed->add_output() = item;
        if (!error_message.empty())
            changed->mutable_error()->set_message(error_message);
    }
    emit(event);
}

NodeInputs WorkflowRunner::gather_inputs(const std::string& node_id) const {
    std::lock_guard<std::mutex> lock(mutex_);

    NodeInputs inputs;
    for (const auto& edge : document_.edges()) {
        if (edge.to_node() != node_id)
            continue;

        // Outputs are stored per port, so an edge leaving the port a Condition
        // or Filter did not emit on finds nothing and carries nothing.
        auto output = outputs_.find(edge.from_node());
        if (output == outputs_.end())
            continue;
        auto port = output->second.find(edge.from_port());
        if (port == output->second.end())
            continue;

        inputs.items.insert(inputs.items.end(), port->second.begin(), port->second.end());
        auto& per_port = inputs.by_port[edge.to_port()];
        per_port.insert(per_port.end(), port->second.begin(), port->second.end());
    }
    return inputs;
}

bool WorkflowRunner::upstream_is_dead(const std::string& node_id) const {
    std::lock_guard<std::mutex> lock(mutex_);

    bool has_parent = false;
    for (const auto& edge : document_.edges()) {
        if (edge.to_node() != node_id)
            continue;
        has_parent = true;

        auto taken = taken_ports_.find(edge.from_node());
        if (taken != taken_ports_.end() && taken->second != edge.from_port())
            continue;

        auto state = states_.find(edge.from_node());
        if (state != states_.end() && !is_dead(state->second))
            return false;
    }
    // A node with no parents is a root, not an orphan of a dead branch.
    return has_parent;
}

void WorkflowRunner::execute_loop(const WorkflowNode& node,
                                  const std::vector<WorkflowItem>& inputs) {
    const auto& config = node.loop_over_items();

    std::string items_json;
    std::string error;
    bool resolved = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        resolved = resolve_expression(config.items(), context_, &items_json, &error);
    }
    if (!resolved) {
        set_state(node.id(), NodeRunState::NODE_RUN_STATE_FAILED, {}, error);
        return;
    }

    nlohmann::json parsed = nlohmann::json::parse(items_json, nullptr, false);
    if (parsed.is_discarded() || !parsed.is_array()) {
        set_state(node.id(), NodeRunState::NODE_RUN_STATE_FAILED, {},
                  "loop items expression did not resolve to a list");
        return;
    }

    const uint32_t ceiling =
        config.max_iterations() > 0 ? config.max_iterations() : kDefaultLoopCeiling;
    const size_t count = std::min<size_t>(parsed.size(), ceiling);

    std::vector<WorkflowItem> collected;
    for (size_t index = 0; index < count; ++index) {
        if (cancelled_.load(std::memory_order_relaxed))
            break;

        {
            std::lock_guard<std::mutex> lock(mutex_);
            context_.has_current_item = true;
            context_.current_item_json = parsed[index].dump();
        }

        // The body is a straight chain: each node sees the previous node's
        // output, seeded by the current item.
        std::vector<WorkflowItem> carried;
        WorkflowItem seed;
        seed.set_json(parsed[index].dump());
        carried.push_back(seed);

        bool body_failed = false;
        for (const std::string& body_id : config.body_node_ids()) {
            const WorkflowNode* body_node = nullptr;
            for (const WorkflowNode& candidate : document_.nodes()) {
                if (candidate.id() == body_id) {
                    body_node = &candidate;
                    break;
                }
            }
            if (body_node == nullptr)
                continue;

            NodeExecution execution;
            std::string body_error;
            ExpressionContext snapshot;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                snapshot = context_;
            }

            NodeInputs body_inputs;
            body_inputs.items = carried;
            body_inputs.by_port["in"] = carried;

            const rac_result_t result = execute_node(*body_node, body_inputs, snapshot, run_id_,
                                                     &cancelled_, &execution, &body_error);
            if (result != RAC_SUCCESS) {
                set_state(body_id, NodeRunState::NODE_RUN_STATE_FAILED, {}, body_error);
                body_failed = true;
                break;
            }

            carried = execution.items;
            set_state(body_id, NodeRunState::NODE_RUN_STATE_SUCCEEDED, carried, {});

            std::lock_guard<std::mutex> lock(mutex_);
            outputs_[body_id]["out"] = carried;
            if (!body_node->name().empty()) {
                std::vector<std::string> bodies;
                bodies.reserve(carried.size());
                for (const WorkflowItem& item : carried)
                    bodies.push_back(item.json());
                context_.node_outputs[body_node->name()] = bodies;
            }
        }

        if (body_failed) {
            set_state(node.id(), NodeRunState::NODE_RUN_STATE_FAILED, {},
                      "a node inside the loop failed");
            return;
        }

        collected.insert(collected.end(), carried.begin(), carried.end());
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        context_.has_current_item = false;
        context_.current_item_json.clear();
        outputs_[node.id()]["out"] = collected;
        if (!node.name().empty()) {
            std::vector<std::string> bodies;
            bodies.reserve(collected.size());
            for (const WorkflowItem& item : collected)
                bodies.push_back(item.json());
            context_.node_outputs[node.name()] = bodies;
        }
    }
    set_state(node.id(), NodeRunState::NODE_RUN_STATE_SUCCEEDED, collected, {});
}

void WorkflowRunner::execute_one(const WorkflowNode& node) {
    if (upstream_is_dead(node.id())) {
        set_state(node.id(), NodeRunState::NODE_RUN_STATE_SKIPPED, {}, {});
        return;
    }

    set_state(node.id(), NodeRunState::NODE_RUN_STATE_RUNNING, {}, {});

    const NodeInputs inputs = gather_inputs(node.id());

    if (node.config_case() == WorkflowNode::kLoopOverItems) {
        execute_loop(node, inputs.items);
        return;
    }

    ExpressionContext snapshot;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot = context_;
    }

    // A trigger with caller-supplied items uses those instead of its own
    // configuration, which is what makes one workflow runnable against
    // different inputs. The host fires a Schedule Trigger by starting a run
    // with the firing's items, so it takes the same override.
    const bool is_trigger_node = node.config_case() == WorkflowNode::kManualTrigger ||
                                 node.config_case() == WorkflowNode::kScheduleTrigger;
    if (is_trigger_node && !initial_items_.empty()) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            outputs_[node.id()]["out"] = initial_items_;
            if (!node.name().empty()) {
                std::vector<std::string> bodies;
                bodies.reserve(initial_items_.size());
                for (const WorkflowItem& item : initial_items_)
                    bodies.push_back(item.json());
                context_.node_outputs[node.name()] = bodies;
            }
        }
        set_state(node.id(), NodeRunState::NODE_RUN_STATE_SUCCEEDED, initial_items_, {});
        return;
    }

    NodeExecution execution;
    std::string error;
    const rac_result_t result =
        execute_node(node, inputs, snapshot, run_id_, &cancelled_, &execution, &error);
    if (result != RAC_SUCCESS) {
        set_state(node.id(), NodeRunState::NODE_RUN_STATE_FAILED, {}, error);
        return;
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        outputs_[node.id()][execution.port] = execution.items;
        if (!execution.secondary_port.empty())
            outputs_[node.id()][execution.secondary_port] = execution.secondary_items;
        if (node.config_case() == WorkflowNode::kCondition)
            taken_ports_[node.id()] = execution.port;
        if (!node.name().empty()) {
            std::vector<std::string> bodies;
            bodies.reserve(execution.items.size());
            for (const WorkflowItem& item : execution.items)
                bodies.push_back(item.json());
            context_.node_outputs[node.name()] = bodies;
        }
    }
    set_state(node.id(), NodeRunState::NODE_RUN_STATE_SUCCEEDED, execution.items, {});
}

void WorkflowRunner::run() {
    {
        runanywhere::v1::WorkflowRunEvent event;
        event.set_run_id(run_id_);
        runanywhere::v1::RunStarted* started = event.mutable_run_started();
        started->set_workflow_id(document_.id());
        started->set_started_at_ms(now_ms());
        emit(event);
    }

    const std::vector<std::string> order = topological_order(document_);

    bool any_failed = false;
    for (const std::string& node_id : order) {
        if (cancelled_.load(std::memory_order_relaxed))
            break;

        const WorkflowNode* node = nullptr;
        for (const WorkflowNode& candidate : document_.nodes()) {
            if (candidate.id() == node_id) {
                node = &candidate;
                break;
            }
        }
        if (node == nullptr)
            continue;

        execute_one(*node);

        std::lock_guard<std::mutex> lock(mutex_);
        if (states_[node_id] == NodeRunState::NODE_RUN_STATE_FAILED)
            any_failed = true;
    }

    WorkflowRunState final_state;
    if (cancelled_.load(std::memory_order_relaxed)) {
        final_state = WorkflowRunState::WORKFLOW_RUN_STATE_CANCELLED;
    } else if (any_failed) {
        final_state = WorkflowRunState::WORKFLOW_RUN_STATE_FAILED;
    } else {
        final_state = WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED;
    }

    runanywhere::v1::WorkflowRunRecord snapshot;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        record_.set_state(final_state);
        record_.set_finished_at_ms(now_ms());
        snapshot = record_;
    }

    // Persist before the finish event so a host that reacts by loading the
    // record always finds it on disk.
    const rac_result_t stored = store_save_run(snapshot);
    if (stored != RAC_SUCCESS) {
        RAC_LOG_WARNING(kLogCategory, "could not persist run '%s': %s", run_id_.c_str(),
                        rac_error_message(stored));
    }

    runanywhere::v1::WorkflowRunEvent event;
    event.set_run_id(run_id_);
    runanywhere::v1::RunFinished* finished = event.mutable_run_finished();
    finished->set_state(final_state);
    finished->set_finished_at_ms(snapshot.finished_at_ms());
    emit(event);
}

}  // namespace rac::agent
