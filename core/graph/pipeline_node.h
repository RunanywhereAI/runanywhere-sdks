// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Abstract base for L3 operators inside an L4 DAG.
//
// A PipelineNode is the C++ equivalent of a node in the VoiceAgent /
// RAG YAML. It owns its input/output edges and its worker thread. The
// `run()` method is called on a dedicated thread (Asio strand on
// macOS/Android/Linux, GCD serial queue on iOS, event loop turn on WASM).
//
// Concrete subclasses (implemented in solutions/voice-agent/, solutions/rag/,
// etc.) override `run()` and consume from their input edges while emitting
// to their output edges. The DAG scheduler owns the thread and the
// CancelToken hierarchy.

#ifndef RA_CORE_PIPELINE_NODE_H
#define RA_CORE_PIPELINE_NODE_H

#include <chrono>
#include <memory>
#include <string>
#include <string_view>

#include "cancel_token.h"

namespace ra::core {

enum class NodeState {
    kCreated,
    kRunning,
    kCompleted,
    kCancelled,
    kErrored,
};

struct NodeMetrics {
    std::chrono::nanoseconds total_wall_time{0};
    std::uint64_t            items_produced{0};
    std::uint64_t            items_consumed{0};
    std::uint64_t            backpressure_events{0};
};

class PipelineNode {
public:
    PipelineNode(std::string name, std::shared_ptr<CancelToken> cancel)
        : name_(std::move(name)), cancel_(std::move(cancel)) {}

    PipelineNode(const PipelineNode&)            = delete;
    PipelineNode& operator=(const PipelineNode&) = delete;
    PipelineNode(PipelineNode&&)                 = delete;
    PipelineNode& operator=(PipelineNode&&)      = delete;
    virtual ~PipelineNode() = default;

    std::string_view name() const noexcept { return name_; }
    NodeState        state() const noexcept { return state_; }
    const NodeMetrics& metrics() const noexcept { return metrics_; }

    // Entry point. The scheduler calls this on the node's dedicated thread
    // once; the call returns when the node finishes (normally or due to
    // cancellation). Implementations MUST check cancel_->is_cancelled()
    // in any blocking loop.
    virtual void run() = 0;

    // Invoked by the scheduler before any run() call, after all edges are
    // wired. Use for eager model loading; any failure must throw so the
    // scheduler can tear down the DAG cleanly.
    virtual void initialize() {}

    // Invoked after run() returns — regardless of success or cancellation.
    // Release any resources acquired in initialize() / run(). Must not
    // throw.
    virtual void finalize() noexcept {}

protected:
    // Called by subclasses to mark transitions for metrics and logging.
    void set_state(NodeState s) noexcept { state_ = s; }
    NodeMetrics& mutable_metrics() noexcept { return metrics_; }

    const std::shared_ptr<CancelToken>& cancel_token() const noexcept {
        return cancel_;
    }

private:
    std::string                  name_;
    std::shared_ptr<CancelToken> cancel_;
    NodeState                    state_   = NodeState::kCreated;
    NodeMetrics                  metrics_;
};

}  // namespace ra::core

#endif  // RA_CORE_PIPELINE_NODE_H
