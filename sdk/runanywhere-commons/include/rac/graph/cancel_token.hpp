// SPDX-License-Identifier: Apache-2.0
//
// rac/graph/cancel_token.hpp — v3.1 Phase 9 DAG primitive (GAP 05).
//
// Hierarchical cancellation token. Parent cancel cascades to all
// children atomically. Children can be added/removed dynamically.
// Thread-safe: cancel() is callable from any thread, is_cancelled()
// is lock-free on the hot path.
//
// Usage:
//     auto parent = std::make_shared<rac::graph::CancelToken>();
//     auto child  = std::make_shared<rac::graph::CancelToken>(parent);
//     // ... pass `child` to a pipeline node ...
//     parent->cancel();   // child->is_cancelled() returns true
//
// The token is INTENTIONALLY minimal — no callbacks, no waiters,
// no reason codes. Those can be layered above if a consumer needs
// them. Keeping the primitive small keeps the lock-free fast path
// predictable.

#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

namespace rac::graph {

class CancelToken : public std::enable_shared_from_this<CancelToken> {
public:
    CancelToken() = default;

    /// Construct a child token that inherits its parent's cancel state.
    /// If `parent` is already cancelled, the new child is cancelled too.
    explicit CancelToken(std::shared_ptr<CancelToken> parent)
        : parent_(std::move(parent)) {
        if (parent_ && parent_->is_cancelled()) {
            cancelled_.store(true, std::memory_order_relaxed);
        }
    }

    CancelToken(const CancelToken&)            = delete;
    CancelToken& operator=(const CancelToken&) = delete;

    /// Lock-free check — called on every pipeline iteration.
    bool is_cancelled() const noexcept {
        return cancelled_.load(std::memory_order_acquire);
    }

    /// Cancel this token and all registered children. Idempotent.
    void cancel() {
        const bool was_already_cancelled = cancelled_.exchange(
            true, std::memory_order_release);
        if (was_already_cancelled) return;

        // Cascade to children. Take the lock once and release after
        // copying the list — avoids a re-entrant cancel deadlock
        // if a child's ptr points back at us somehow.
        std::vector<std::shared_ptr<CancelToken>> snapshot;
        {
            std::lock_guard<std::mutex> lock(children_mu_);
            snapshot.reserve(children_.size());
            for (auto& weak : children_) {
                if (auto sp = weak.lock()) {
                    snapshot.push_back(std::move(sp));
                }
            }
        }
        for (auto& child : snapshot) {
            child->cancel();
        }
    }

    /// Register `child` for cascade. Should usually be called by
    /// `CancelToken::create_child()` below, not directly.
    void add_child(std::shared_ptr<CancelToken> child) {
        if (!child) return;
        std::lock_guard<std::mutex> lock(children_mu_);
        children_.emplace_back(child);
    }

    /// Factory helper: create a child of `this` + wire the back-link.
    /// If `this` is already cancelled, the child starts cancelled.
    std::shared_ptr<CancelToken> create_child() {
        auto child = std::make_shared<CancelToken>(shared_from_this());
        add_child(child);
        return child;
    }

private:
    std::atomic<bool>                           cancelled_{false};
    std::shared_ptr<CancelToken>                parent_;
    std::mutex                                  children_mu_;
    std::vector<std::weak_ptr<CancelToken>>     children_;
};

}  // namespace rac::graph
