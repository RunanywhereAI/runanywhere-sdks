// SPDX-License-Identifier: Apache-2.0
//
// rac/graph/stream_edge.hpp — v3.1 Phase 9 DAG primitive (GAP 05).
//
// Typed, bounded, thread-safe queue connecting two DAG nodes. Three
// overflow policies:
//
//   OverflowPolicy::BlockProducer
//     Push blocks until the consumer drains a slot. Use when message
//     loss is unacceptable (e.g. LLM token stream — every token is
//     semantically significant).
//
//   OverflowPolicy::DropNewest
//     Push silently drops when full. Use when latest frames matter
//     more than history (e.g. transient state updates).
//
//   OverflowPolicy::DropOldest
//     Push evicts the oldest pending item and pushes the new one.
//     Use for audio frame streams where a slow consumer should see
//     fresh samples.
//
// The edge uses a condition_variable + mutex for producer wake-up
// (simpler than lock-free for the mixed policy case). For single-
// producer audio fan-out where latency matters, use RingBuffer
// directly (see `ring_buffer.hpp`).

#pragma once

#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>
#include <optional>

#include "rac/graph/cancel_token.hpp"

namespace rac::graph {

enum class OverflowPolicy {
    BlockProducer,
    DropNewest,
    DropOldest,
};

template <typename T>
class StreamEdge {
public:
    explicit StreamEdge(size_t capacity,
                        OverflowPolicy policy = OverflowPolicy::BlockProducer)
        : capacity_(capacity), policy_(policy) {}

    StreamEdge(const StreamEdge&)            = delete;
    StreamEdge& operator=(const StreamEdge&) = delete;

    /// Push an item. Return true if enqueued, false if dropped or
    /// rejected due to cancellation. For BlockProducer, blocks until
    /// space is available OR cancel is observed.
    bool push(T item, CancelToken* cancel = nullptr) {
        std::unique_lock<std::mutex> lock(mu_);

        switch (policy_) {
        case OverflowPolicy::DropNewest:
            if (queue_.size() >= capacity_) return false;
            break;
        case OverflowPolicy::DropOldest:
            while (queue_.size() >= capacity_) {
                queue_.pop_front();
            }
            break;
        case OverflowPolicy::BlockProducer:
            while (queue_.size() >= capacity_) {
                if (cancel && cancel->is_cancelled()) return false;
                // Waiting: release the lock, re-acquire when woken.
                // Timed wait so a cancel that arrives AFTER we start
                // waiting is picked up within 50ms.
                producer_cv_.wait_for(lock, std::chrono::milliseconds(50));
            }
            break;
        }

        if (cancel && cancel->is_cancelled()) return false;

        queue_.emplace_back(std::move(item));
        consumer_cv_.notify_one();
        return true;
    }

    /// Pop the next item. Blocks until one arrives OR cancel fires.
    /// Returns nullopt on cancel.
    std::optional<T> pop(CancelToken* cancel = nullptr) {
        std::unique_lock<std::mutex> lock(mu_);
        while (queue_.empty()) {
            if (cancel && cancel->is_cancelled()) return std::nullopt;
            if (closed_) return std::nullopt;
            consumer_cv_.wait_for(lock, std::chrono::milliseconds(50));
        }
        T item = std::move(queue_.front());
        queue_.pop_front();
        producer_cv_.notify_one();
        return item;
    }

    /// Non-blocking try_pop. Returns nullopt if empty.
    std::optional<T> try_pop() {
        std::unique_lock<std::mutex> lock(mu_);
        if (queue_.empty()) return std::nullopt;
        T item = std::move(queue_.front());
        queue_.pop_front();
        producer_cv_.notify_one();
        return item;
    }

    /// Signal end-of-stream. Pending consumers observe nullopt.
    void close() {
        {
            std::lock_guard<std::mutex> lock(mu_);
            closed_ = true;
        }
        consumer_cv_.notify_all();
        producer_cv_.notify_all();
    }

    size_t approximate_size() const {
        std::lock_guard<std::mutex> lock(mu_);
        return queue_.size();
    }

    size_t capacity() const noexcept { return capacity_; }

private:
    const size_t                    capacity_;
    const OverflowPolicy            policy_;
    mutable std::mutex              mu_;
    std::condition_variable         producer_cv_;
    std::condition_variable         consumer_cv_;
    std::deque<T>                   queue_;
    bool                            closed_{false};
};

}  // namespace rac::graph
