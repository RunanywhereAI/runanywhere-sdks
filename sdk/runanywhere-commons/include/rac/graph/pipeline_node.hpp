// SPDX-License-Identifier: Apache-2.0
//
// rac/graph/pipeline_node.hpp — v3.1 Phase 9 DAG primitive (GAP 05 Phase 2).
//
// Node abstraction for the streaming DAG runtime. Each node owns:
//   * one worker thread that drains its input edge
//   * a typed input edge (StreamEdge<In>) and output edge (StreamEdge<Out>)
//   * a child CancelToken forked from the scheduler's root token
//
// Contract
// --------
//   `start(parent_cancel)`   — spawn the worker thread; must not be called
//                              more than once. Idempotent no-ops otherwise.
//   `stop()`                 — trigger cancel + close input edge; the
//                              worker loop exits on the next edge drain.
//                              Non-blocking.
//   `join()`                 — block until the worker thread has exited
//                              and the output edge has been closed. Safe to
//                              call after stop() or after the worker exits
//                              naturally on input close.
//
// The base `run()` loop is:
//   while (!cancelled) {
//       auto item = input_->pop(cancel_.get());
//       if (!item) break;                // closed or cancelled
//       process(std::move(*item), *output_);
//   }
//   output_->close();
//
// Subclasses
// ----------
//   `PrimitiveNode<In, Out, Op>` — wraps any callable with signature
//       void(In&& in, StreamEdge<Out>& out)
//     Use to adapt a `rac_engine_vtable_t` primitive (stt_transcribe,
//     llm_generate, …) or any plain C++ functor into a pipeline node.
//
//   `SplitNode<T>` — fan-out 1 → N. Copies each popped item to N output
//                    edges. Requires T to be copy-constructible.
//
//   `MergeNode<T>` — fan-in N → 1. One worker thread per input drains into
//                    the single output. Output closes after *all* input
//                    workers exit.
//
// Type-erased base
// ----------------
//   `IPipelineNode` allows GraphScheduler to store heterogeneous nodes in
//   a single container without leaking the In/Out template parameters.

#pragma once

#include <atomic>
#include <cstddef>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/memory_pool.hpp"
#include "rac/graph/stream_edge.hpp"

namespace rac::graph {

class IPipelineNode {
public:
    virtual ~IPipelineNode() = default;

    /// Spawn the worker thread(s). `parent_cancel` — if non-null — is the
    /// scheduler's root token; the node forks a child off it so cancelling
    /// the parent cascades to the node automatically.
    virtual void start(std::shared_ptr<CancelToken> parent_cancel) = 0;

    /// Trigger cancellation + close upstream edges. Non-blocking.
    virtual void stop() = 0;

    /// Wait for every worker thread owned by this node to finish. Safe to
    /// call after stop(); safe to call multiple times.
    virtual void join() = 0;

    /// Node identity — used by the scheduler's trace output.
    virtual const char* name() const noexcept = 0;
};

// ---------------------------------------------------------------------------
// PipelineNode<In, Out>
// ---------------------------------------------------------------------------

template <typename In, typename Out>
class PipelineNode : public IPipelineNode {
public:
    using InputEdge  = StreamEdge<In>;
    using OutputEdge = StreamEdge<Out>;

    explicit PipelineNode(std::string name,
                          size_t input_capacity  = 16,
                          size_t output_capacity = 16,
                          OverflowPolicy policy  = OverflowPolicy::BlockProducer)
        : name_(std::move(name)),
          input_(std::make_shared<InputEdge>(input_capacity, policy)),
          output_(std::make_shared<OutputEdge>(output_capacity, policy)) {}

    PipelineNode(const PipelineNode&)            = delete;
    PipelineNode& operator=(const PipelineNode&) = delete;

    void start(std::shared_ptr<CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true)) return;
        cancel_ = parent_cancel ? parent_cancel->create_child()
                                : std::make_shared<CancelToken>();
        worker_ = std::thread([this] { run(); });
    }

    void stop() override {
        if (cancel_) cancel_->cancel();
        if (input_)  input_->close();
    }

    void join() override {
        if (worker_.joinable()) worker_.join();
        if (output_) output_->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

    // ---- Edge accessors --------------------------------------------------

    std::shared_ptr<InputEdge>  input()  { return input_; }
    std::shared_ptr<OutputEdge> output() { return output_; }

    /// Replace the input edge. Used by GraphScheduler::connect() to share a
    /// single edge between a producer's output and a consumer's input (one
    /// bounded buffer ⇒ natural backpressure, no bridge thread). MUST be
    /// called before start().
    void set_input(std::shared_ptr<InputEdge> in) { input_ = std::move(in); }
    void set_output(std::shared_ptr<OutputEdge> out) { output_ = std::move(out); }

    CancelToken* cancel_token() const noexcept { return cancel_.get(); }

protected:
    /// Called once per input item. Implementations push zero or more Out
    /// values into `out`. May block on backpressure; must honour cancel_.
    virtual void process(In in, OutputEdge& out) = 0;

    /// Optional hook — called after the main loop exits, before the output
    /// edge is closed. Useful for flushing stateful nodes.
    virtual void on_drained(OutputEdge& /*out*/) {}

    std::shared_ptr<CancelToken> cancel_;

private:
    void run() {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto item = input_->pop(cancel_.get());
            if (!item) break;
            process(std::move(*item), *output_);
        }
        on_drained(*output_);
        output_->close();
    }

    std::string                 name_;
    std::shared_ptr<InputEdge>  input_;
    std::shared_ptr<OutputEdge> output_;
    std::thread                 worker_;
    std::atomic<bool>           started_{false};
};

// ---------------------------------------------------------------------------
// PrimitiveNode<In, Out, Op>
// ---------------------------------------------------------------------------
//
// Wraps any callable matching `void(In&&, StreamEdge<Out>&)` as a pipeline
// node. The typical adapter around a C ABI primitive (e.g. the STT vtable's
// `transcribe` fn) captures the vtable pointer + engine handle in a lambda
// and pushes each emitted chunk into `out`.

template <typename In, typename Out, typename Op>
class PrimitiveNode : public PipelineNode<In, Out> {
public:
    PrimitiveNode(std::string name,
                  Op op,
                  size_t input_capacity  = 16,
                  size_t output_capacity = 16,
                  OverflowPolicy policy  = OverflowPolicy::BlockProducer)
        : PipelineNode<In, Out>(std::move(name), input_capacity,
                                output_capacity, policy),
          op_(std::move(op)) {}

protected:
    void process(In in, StreamEdge<Out>& out) override {
        op_(std::move(in), out);
    }

private:
    Op op_;
};

// Deduction helper — construct without repeating the Op type.
template <typename In, typename Out, typename Op>
std::shared_ptr<PrimitiveNode<In, Out, std::decay_t<Op>>>
make_primitive_node(std::string name, Op&& op,
                    size_t input_capacity  = 16,
                    size_t output_capacity = 16,
                    OverflowPolicy policy  = OverflowPolicy::BlockProducer) {
    return std::make_shared<PrimitiveNode<In, Out, std::decay_t<Op>>>(
        std::move(name), std::forward<Op>(op),
        input_capacity, output_capacity, policy);
}

// ---------------------------------------------------------------------------
// SplitNode<T> — fan-out 1 → N
// ---------------------------------------------------------------------------

template <typename T>
class SplitNode : public IPipelineNode {
public:
    using Edge = StreamEdge<T>;

    SplitNode(std::string name,
              size_t num_outputs,
              size_t capacity       = 16,
              OverflowPolicy policy = OverflowPolicy::BlockProducer)
        : name_(std::move(name)),
          input_(std::make_shared<Edge>(capacity, policy)) {
        outputs_.reserve(num_outputs);
        for (size_t i = 0; i < num_outputs; ++i) {
            outputs_.emplace_back(std::make_shared<Edge>(capacity, policy));
        }
    }

    SplitNode(const SplitNode&)            = delete;
    SplitNode& operator=(const SplitNode&) = delete;

    std::shared_ptr<Edge> input() { return input_; }
    void set_input(std::shared_ptr<Edge> in) { input_ = std::move(in); }

    std::shared_ptr<Edge> output(size_t idx) { return outputs_.at(idx); }
    size_t output_count() const noexcept { return outputs_.size(); }

    void start(std::shared_ptr<CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true)) return;
        cancel_ = parent_cancel ? parent_cancel->create_child()
                                : std::make_shared<CancelToken>();
        worker_ = std::thread([this] { run(); });
    }

    void stop() override {
        if (cancel_) cancel_->cancel();
        if (input_)  input_->close();
    }

    void join() override {
        if (worker_.joinable()) worker_.join();
        for (auto& out : outputs_) out->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

private:
    void run() {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto item = input_->pop(cancel_.get());
            if (!item) break;
            // Copy to N-1 outputs, move into the last one. Requires T to be
            // copy-constructible; if that's ever a problem swap in shared_ptr.
            for (size_t i = 0; i + 1 < outputs_.size(); ++i) {
                outputs_[i]->push(*item, cancel_.get());
            }
            if (!outputs_.empty()) {
                outputs_.back()->push(std::move(*item), cancel_.get());
            }
        }
    }

    std::string                         name_;
    std::shared_ptr<Edge>               input_;
    std::vector<std::shared_ptr<Edge>>  outputs_;
    std::shared_ptr<CancelToken>        cancel_;
    std::thread                         worker_;
    std::atomic<bool>                   started_{false};
};

// ---------------------------------------------------------------------------
// MergeNode<T> — fan-in N → 1
// ---------------------------------------------------------------------------

template <typename T>
class MergeNode : public IPipelineNode {
public:
    using Edge = StreamEdge<T>;

    MergeNode(std::string name,
              size_t num_inputs,
              size_t capacity       = 16,
              OverflowPolicy policy = OverflowPolicy::BlockProducer)
        : name_(std::move(name)),
          output_(std::make_shared<Edge>(capacity, policy)) {
        inputs_.reserve(num_inputs);
        for (size_t i = 0; i < num_inputs; ++i) {
            inputs_.emplace_back(std::make_shared<Edge>(capacity, policy));
        }
    }

    MergeNode(const MergeNode&)            = delete;
    MergeNode& operator=(const MergeNode&) = delete;

    std::shared_ptr<Edge> input(size_t idx) { return inputs_.at(idx); }
    void set_input(size_t idx, std::shared_ptr<Edge> in) {
        inputs_.at(idx) = std::move(in);
    }
    size_t input_count() const noexcept { return inputs_.size(); }

    std::shared_ptr<Edge> output() { return output_; }

    void start(std::shared_ptr<CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true)) return;
        cancel_ = parent_cancel ? parent_cancel->create_child()
                                : std::make_shared<CancelToken>();
        workers_.reserve(inputs_.size());
        active_.store(static_cast<int>(inputs_.size()),
                      std::memory_order_release);
        for (size_t i = 0; i < inputs_.size(); ++i) {
            auto in = inputs_[i];
            workers_.emplace_back([this, in] { drain_one(in); });
        }
    }

    void stop() override {
        if (cancel_) cancel_->cancel();
        for (auto& in : inputs_) in->close();
    }

    void join() override {
        for (auto& th : workers_) {
            if (th.joinable()) th.join();
        }
        workers_.clear();
        // Output was already closed by the last drain-worker; closing
        // again is a no-op but keeps the post-condition obvious.
        if (output_) output_->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

private:
    void drain_one(std::shared_ptr<Edge> in) {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto item = in->pop(cancel_.get());
            if (!item) break;
            output_->push(std::move(*item), cancel_.get());
        }
        // Last input-drainer closes the output so downstream consumers
        // see EOF exactly once.
        if (active_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            output_->close();
        }
    }

    std::string                         name_;
    std::vector<std::shared_ptr<Edge>>  inputs_;
    std::shared_ptr<Edge>               output_;
    std::shared_ptr<CancelToken>        cancel_;
    std::vector<std::thread>            workers_;
    std::atomic<int>                    active_{0};
    std::atomic<bool>                   started_{false};
};

}  // namespace rac::graph
