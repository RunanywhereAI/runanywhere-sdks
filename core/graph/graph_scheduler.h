// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Platform-conditional scheduler that owns one thread per PipelineNode.
//
//   - macOS / Linux / Android: std::jthread (C++20) — each node gets a raw
//     thread. Asio would add a dependency we don't need for the current
//     node count (< 20 per pipeline).
//   - iOS: GCD DispatchQueue (serial queue per node + single concurrent
//     queue for completion fan-in).
//   - WASM: emscripten_set_timeout loop — single threaded, cooperative.
//
// The scheduler's lifecycle is tied to its owning Pipeline. On cancel, it
// cancels the root CancelToken (which propagates down), waits for every
// node thread to join, and invokes the completion callback.

#ifndef RA_CORE_GRAPH_SCHEDULER_H
#define RA_CORE_GRAPH_SCHEDULER_H

#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "cancel_token.h"
#include "pipeline_node.h"

namespace ra::core {

class GraphScheduler {
public:
    using CompletionHandler = std::function<void(int /*status*/,
                                                 std::string /*msg*/)>;

    GraphScheduler();
    ~GraphScheduler();

    GraphScheduler(const GraphScheduler&)            = delete;
    GraphScheduler& operator=(const GraphScheduler&) = delete;
    GraphScheduler(GraphScheduler&&)                 = delete;
    GraphScheduler& operator=(GraphScheduler&&)      = delete;

    // Adds a node. The scheduler takes ownership; call before start().
    void add_node(std::shared_ptr<PipelineNode> node);

    // Sets the root cancellation token. All node tokens are children.
    void set_cancel_token(std::shared_ptr<CancelToken> token) {
        root_cancel_ = std::move(token);
    }

    const std::shared_ptr<CancelToken>& cancel_token() const noexcept {
        return root_cancel_;
    }

    // Set the completion handler. Fires once, on the cancelling thread
    // (or the last-finishing node's thread on normal completion).
    void set_completion_handler(CompletionHandler handler) {
        on_complete_ = std::move(handler);
    }

    // Calls initialize() on every node, then launches one thread per node
    // running node->run(). Non-blocking.
    void start();

    // Requests cancellation and joins all threads. Blocking. Safe to call
    // multiple times.
    void stop_and_join();

private:
    void thread_body(std::shared_ptr<PipelineNode> node);
    void maybe_signal_completion();

    std::shared_ptr<CancelToken>               root_cancel_;
    std::vector<std::shared_ptr<PipelineNode>> nodes_;
    std::vector<std::thread>                   threads_;
    CompletionHandler                          on_complete_;
    std::atomic<std::size_t>                   alive_count_{0};
    std::atomic<bool>                          completion_fired_{false};
    std::atomic<bool>                          error_seen_{false};
    std::string                                first_error_message_;
    std::mutex                                 error_mu_;
};

}  // namespace ra::core

#endif  // RA_CORE_GRAPH_SCHEDULER_H
