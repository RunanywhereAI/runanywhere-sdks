// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Hierarchical cancellation tokens.
//
// Every pipeline operator receives a CancelToken. Cancelling a parent token
// cancels all children recursively, and fires any callbacks registered via
// on_cancel(). Callbacks fire exactly once, on the cancelling thread.
//
// Tokens are cheap to create — the expected tree is on the order of dozens
// of nodes per pipeline. A CancelToken is a std::shared_ptr<impl>; pass by
// value freely.

#ifndef RA_CORE_CANCEL_TOKEN_H
#define RA_CORE_CANCEL_TOKEN_H

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace ra::core {

class CancelToken {
public:
    // Factory — all tokens must be heap-allocated via shared_ptr.
    static std::shared_ptr<CancelToken> create() {
        return std::shared_ptr<CancelToken>(new CancelToken());
    }

    CancelToken(const CancelToken&)            = delete;
    CancelToken& operator=(const CancelToken&) = delete;
    CancelToken(CancelToken&&)                 = delete;
    CancelToken& operator=(CancelToken&&)      = delete;

    // Idempotent. Safe to call from any thread.
    void cancel() noexcept {
        bool expected = false;
        if (!cancelled_.compare_exchange_strong(expected, true,
                                                 std::memory_order_acq_rel)) {
            return;  // Already cancelled.
        }

        std::vector<std::shared_ptr<CancelToken>> children_snapshot;
        std::vector<std::function<void()>>        callbacks_snapshot;
        {
            std::lock_guard<std::mutex> lk(mu_);
            children_snapshot.swap(children_);
            callbacks_snapshot.swap(callbacks_);
        }

        for (auto& cb : callbacks_snapshot) {
            try {
                cb();
            } catch (...) {
                // Swallow — a failing callback must not block propagation.
            }
        }
        for (auto& child : children_snapshot) {
            if (child) child->cancel();
        }
    }

    bool is_cancelled() const noexcept {
        return cancelled_.load(std::memory_order_acquire);
    }

    // Creates a child that auto-cancels when this token cancels. Safe to
    // call from any thread. If the parent is already cancelled, the child
    // is returned in cancelled state.
    std::shared_ptr<CancelToken> child() {
        auto c = create();
        {
            std::lock_guard<std::mutex> lk(mu_);
            if (cancelled_.load(std::memory_order_acquire)) {
                c->cancel();
                return c;
            }
            children_.push_back(c);
        }
        return c;
    }

    // Registers a callback invoked exactly once on cancellation. Callbacks
    // run on the thread that calls cancel(). If the token is already
    // cancelled, the callback fires synchronously before this returns.
    void on_cancel(std::function<void()> cb) {
        {
            std::lock_guard<std::mutex> lk(mu_);
            if (!cancelled_.load(std::memory_order_acquire)) {
                callbacks_.push_back(std::move(cb));
                return;
            }
        }
        // Already cancelled — invoke synchronously.
        try {
            cb();
        } catch (...) {
            // Swallow.
        }
    }

private:
    CancelToken() = default;

    std::atomic<bool>                                cancelled_{false};
    std::mutex                                       mu_;
    std::vector<std::shared_ptr<CancelToken>>        children_;
    std::vector<std::function<void()>>               callbacks_;
};

}  // namespace ra::core

#endif  // RA_CORE_CANCEL_TOKEN_H
