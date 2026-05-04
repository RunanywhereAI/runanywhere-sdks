// SPDX-License-Identifier: Apache-2.0
//
// rac/graph/graph_scheduler.hpp — v3.1 Phase 9 DAG runtime (GAP 05 Phase 2).
//
// Owns the lifecycle of a streaming DAG: a bag of IPipelineNodes plus a
// root CancelToken that cascades to every node.
//
// Design choices
// --------------
//   * One worker thread per node. Each node owns its own thread via
//     PipelineNode::start() — we deliberately don't route node work through
//     a shared pool because nodes are long-lived (one thread per node for
//     the lifetime of the graph, not per-task), and a per-task executor
//     would add a queue hop on every frame.
//
//   * Backpressure for free. `connect(a, b)` swaps in a's output edge as
//     b's input edge so the producer and consumer share a single bounded
//     StreamEdge. When the consumer stalls, the shared edge fills up and
//     BlockProducer makes the producer wait. No drops, no OOM.
//
//   * Cancellation is hierarchical. `cancel_all()` cancels the root token;
//     every node's child token cascades; edge blocked pushes/pops return
//     nullopt within ~50 ms.
//
//   * `thread_pool_size` is informational for now; it sizes the optional
//     executor pool used by future helper tasks (e.g. non-node bridge
//     threads). The current implementation drives all node work directly
//     from node-owned threads.

#pragma once

#include <cstddef>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/pipeline_node.hpp"
#include "rac/graph/stream_edge.hpp"

namespace rac::graph {

class GraphScheduler {
public:
    explicit GraphScheduler(
        size_t thread_pool_size = std::thread::hardware_concurrency());

    ~GraphScheduler();

    GraphScheduler(const GraphScheduler&)            = delete;
    GraphScheduler& operator=(const GraphScheduler&) = delete;

    /// Register a node. Nodes must be added before `start()`. Not thread-safe
    /// versus start/stop; call from the configuring thread only.
    void add_node(std::shared_ptr<IPipelineNode> node);

    /// Wire the producer's output edge to the consumer's input edge. The
    /// two nodes share the SAME bounded StreamEdge after this call — which
    /// is what gives us backpressure without extra bridge threads. Must be
    /// called before start().
    template <typename ProdIn, typename Mid, typename ConsOut>
    void connect(PipelineNode<ProdIn, Mid>& producer,
                 PipelineNode<Mid,  ConsOut>& consumer) {
        consumer.set_input(producer.output());
    }

    /// Overload that wires a PipelineNode into a SplitNode input.
    template <typename ProdIn, typename T>
    void connect(PipelineNode<ProdIn, T>& producer,
                 SplitNode<T>& split) {
        split.set_input(producer.output());
    }

    /// Overload that wires a SplitNode output into a consumer PipelineNode.
    template <typename T, typename ConsOut>
    void connect(SplitNode<T>& split, size_t split_out_idx,
                 PipelineNode<T, ConsOut>& consumer) {
        consumer.set_input(split.output(split_out_idx));
    }

    /// Overload that wires a producer into one of a MergeNode's inputs.
    template <typename ProdIn, typename T>
    void connect(PipelineNode<ProdIn, T>& producer,
                 MergeNode<T>& merge, size_t merge_in_idx) {
        merge.set_input(merge_in_idx, producer.output());
    }

    /// Overload that wires a MergeNode output into a consumer PipelineNode.
    template <typename T, typename ConsOut>
    void connect(MergeNode<T>& merge,
                 PipelineNode<T, ConsOut>& consumer) {
        consumer.set_input(merge.output());
    }

    /// Spawn every node's worker thread. Idempotent — subsequent calls are
    /// no-ops until stop().
    void start();

    /// Ask every node to stop (closes input edges, cancels token). Non-
    /// blocking; follow with wait() to join.
    void stop();

    /// Block until every node's worker has joined. Safe after stop() or
    /// natural termination (all upstream producers closed their outputs).
    void wait();

    /// Force-cancel the entire graph. Propagates through the root token's
    /// child chain and wakes every blocked push/pop within ~50 ms. Does
    /// not join — call wait() afterwards.
    void cancel_all();

    /// Returns true if any node's worker thread is still alive. Best-
    /// effort — racy with stop()/wait() so only use for diagnostics.
    bool running() const noexcept;

    size_t node_count() const;

    /// Root token — shared with every node added to the scheduler. Exposed
    /// so callers can fork additional children (e.g. for user-spawned
    /// helper threads that must shut down with the graph).
    std::shared_ptr<CancelToken> root_cancel_token() const { return root_; }

private:
    const size_t                                   thread_pool_size_;
    std::shared_ptr<CancelToken>                   root_;
    mutable std::mutex                             mu_;
    std::vector<std::shared_ptr<IPipelineNode>>    nodes_;
    bool                                           started_{false};
    bool                                           stopped_{false};
};

}  // namespace rac::graph
