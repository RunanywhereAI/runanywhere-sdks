// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Typed async edge between two pipeline operators.
//
// Backed by a bounded std::deque<T> protected by a std::mutex and two
// std::condition_variable. Three edge policies:
//
//   BLOCK        — push blocks when full (default, safest)
//   DROP_OLDEST  — pop the oldest item to make room (audio routing)
//   DROP_NEWEST  — drop the incoming item (pager coalescing)
//
// For trivially-copyable hot-path payloads (PCM samples), prefer the
// lock-free RingBuffer<T> directly — StreamEdge is the general-purpose
// message channel that accepts any movable type.
//
// When the associated CancelToken fires, all pending push/pop calls return
// CancelledError.

#ifndef RA_CORE_STREAM_EDGE_H
#define RA_CORE_STREAM_EDGE_H

#include <condition_variable>
#include <cstddef>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <utility>

#include "cancel_token.h"

namespace ra::core {

enum class EdgePolicy {
    kBlock,
    kDropOldest,
    kDropNewest,
};

enum class PushResult {
    kOk,
    kFull,       // only returned from try_push / non-blocking path
    kClosed,
    kCancelled,
    kDropped,    // DROP_* policy silently dropped a value
};

enum class PopResult {
    kOk,
    kEmpty,      // only returned from try_pop / non-blocking path
    kClosed,
    kCancelled,
};

template <typename T>
class StreamEdge {
public:
    StreamEdge(std::size_t                   capacity,
               std::shared_ptr<CancelToken>  token     = nullptr,
               EdgePolicy                    policy    = EdgePolicy::kBlock)
        // Zero capacity would make every push() block forever with nothing
        // to drain it — reject at construction instead of shipping a
        // deadlock primitive. Callers are expected to have already
        // normalized any PipelineSpec `capacity == 0` sentinel to the
        // per-edge default before reaching this point.
        : capacity_(capacity == 0
                     ? throw std::invalid_argument(
                         "StreamEdge capacity must be > 0")
                     : capacity),
          policy_(policy),
          cancel_token_(std::move(token)) {
        if (cancel_token_) {
            // The CancelToken may outlive this edge (common when the token is
            // pipeline-owned and shared across multiple edges). Capture the
            // shared alive_ flag by value — after ~StreamEdge clears the flag
            // under its mutex, any late-firing callback is a no-op and never
            // dereferences the dead `this`.
            auto alive = alive_;
            cancel_token_->on_cancel([this, alive]() {
                std::lock_guard<std::mutex> lk(alive->mu);
                if (alive->live) this->wake_all();
            });
        }
    }

    StreamEdge(const StreamEdge&)            = delete;
    StreamEdge& operator=(const StreamEdge&) = delete;
    StreamEdge(StreamEdge&&)                 = delete;
    StreamEdge& operator=(StreamEdge&&)      = delete;

    ~StreamEdge() {
        // Synchronize with any in-flight cancel callback. After this returns,
        // future invocations of the lambda registered in the constructor see
        // `live=false` and do not touch `*this`.
        std::lock_guard<std::mutex> lk(alive_->mu);
        alive_->live = false;
    }

    // --- Producer side ---

    PushResult push(T value) {
        std::unique_lock<std::mutex> lk(mu_);
        while (buffer_.size() >= capacity_) {
            if (is_cancelled_locked()) return PushResult::kCancelled;
            if (closed_)               return PushResult::kClosed;

            switch (policy_) {
                case EdgePolicy::kBlock:
                    cv_pop_.wait(lk);
                    continue;
                case EdgePolicy::kDropOldest:
                    buffer_.pop_front();
                    break;
                case EdgePolicy::kDropNewest:
                    return PushResult::kDropped;
            }
        }
        if (is_cancelled_locked()) return PushResult::kCancelled;
        if (closed_)               return PushResult::kClosed;
        buffer_.push_back(std::move(value));
        cv_push_.notify_one();
        return PushResult::kOk;
    }

    PushResult try_push(T value) {
        std::lock_guard<std::mutex> lk(mu_);
        if (is_cancelled_locked())         return PushResult::kCancelled;
        if (closed_)                       return PushResult::kClosed;
        if (buffer_.size() >= capacity_)   return PushResult::kFull;
        buffer_.push_back(std::move(value));
        cv_push_.notify_one();
        return PushResult::kOk;
    }

    // --- Consumer side ---

    std::optional<T> pop(PopResult* out_result = nullptr) {
        std::unique_lock<std::mutex> lk(mu_);
        for (;;) {
            if (is_cancelled_locked()) {
                if (out_result) *out_result = PopResult::kCancelled;
                return std::nullopt;
            }
            if (!buffer_.empty()) {
                T value = std::move(buffer_.front());
                buffer_.pop_front();
                cv_pop_.notify_one();
                if (out_result) *out_result = PopResult::kOk;
                return value;
            }
            if (closed_) {
                if (out_result) *out_result = PopResult::kClosed;
                return std::nullopt;
            }
            cv_push_.wait(lk);
        }
    }

    std::optional<T> try_pop(PopResult* out_result = nullptr) {
        std::lock_guard<std::mutex> lk(mu_);
        if (is_cancelled_locked()) {
            if (out_result) *out_result = PopResult::kCancelled;
            return std::nullopt;
        }
        if (!buffer_.empty()) {
            T value = std::move(buffer_.front());
            buffer_.pop_front();
            cv_pop_.notify_one();
            if (out_result) *out_result = PopResult::kOk;
            return value;
        }
        if (closed_) {
            if (out_result) *out_result = PopResult::kClosed;
            return std::nullopt;
        }
        if (out_result) *out_result = PopResult::kEmpty;
        return std::nullopt;
    }

    // --- Lifecycle ---

    void close() noexcept {
        std::lock_guard<std::mutex> lk(mu_);
        closed_ = true;
        cv_push_.notify_all();
        cv_pop_.notify_all();
    }

    // Consumer-side flush. Must not be called concurrently with pop().
    // Used on barge-in to drop buffered sentences atomically.
    void clear_locked() {
        std::lock_guard<std::mutex> lk(mu_);
        buffer_.clear();
        cv_pop_.notify_all();
    }

    bool is_closed() const {
        std::lock_guard<std::mutex> lk(mu_);
        return closed_;
    }

    bool is_cancelled() const {
        return cancel_token_ && cancel_token_->is_cancelled();
    }

    std::size_t capacity() const noexcept { return capacity_; }

    std::size_t size() const {
        std::lock_guard<std::mutex> lk(mu_);
        return buffer_.size();
    }

private:
    bool is_cancelled_locked() const {
        return cancel_token_ && cancel_token_->is_cancelled();
    }

    void wake_all() {
        std::lock_guard<std::mutex> lk(mu_);
        cv_push_.notify_all();
        cv_pop_.notify_all();
    }

    // Shared alive tombstone for CancelToken callback safety. See ctor.
    struct AliveFlag {
        std::mutex mu;
        bool       live = true;
    };

    mutable std::mutex           mu_;
    std::condition_variable      cv_push_;
    std::condition_variable      cv_pop_;
    std::deque<T>                buffer_;
    const std::size_t            capacity_;
    EdgePolicy                   policy_;
    bool                         closed_ = false;
    std::shared_ptr<CancelToken> cancel_token_;
    std::shared_ptr<AliveFlag>   alive_ = std::make_shared<AliveFlag>();
};

}  // namespace ra::core

#endif  // RA_CORE_STREAM_EDGE_H
