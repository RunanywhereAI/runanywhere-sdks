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
        : capacity_(capacity),
          policy_(policy),
          cancel_token_(std::move(token)) {
        if (cancel_token_) {
            cancel_token_->on_cancel([this]() { wake_all(); });
        }
    }

    StreamEdge(const StreamEdge&)            = delete;
    StreamEdge& operator=(const StreamEdge&) = delete;
    StreamEdge(StreamEdge&&)                 = delete;
    StreamEdge& operator=(StreamEdge&&)      = delete;
    ~StreamEdge() = default;

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

    mutable std::mutex           mu_;
    std::condition_variable      cv_push_;
    std::condition_variable      cv_pop_;
    std::deque<T>                buffer_;
    const std::size_t            capacity_;
    EdgePolicy                   policy_;
    bool                         closed_ = false;
    std::shared_ptr<CancelToken> cancel_token_;
};

}  // namespace ra::core

#endif  // RA_CORE_STREAM_EDGE_H
