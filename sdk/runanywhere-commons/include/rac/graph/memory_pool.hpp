// SPDX-License-Identifier: Apache-2.0
//
// rac/graph/memory_pool.hpp — v3.1 Phase 9 DAG primitive (GAP 05 Phase 2).
//
// Bounded, thread-safe pool of reusable T instances. Designed for hot-path
// pipeline nodes that emit frame-sized buffers (audio PCM, LLM token chunks,
// RAG doc shards) and must avoid per-frame heap churn.
//
// Design
// ------
//   * Pre-allocates `capacity` instances up-front via a user-supplied factory
//     (or default-construction).
//   * `acquire()` returns a `std::shared_ptr<T>` whose custom deleter returns
//     the instance to the pool instead of destroying it. If the pool has been
//     destroyed first, the buffer is deleted normally (no dangling pool ref).
//   * `acquire()` blocks when the pool is empty. `try_acquire()` never blocks.
//   * `acquire_for(timeout)` blocks up to the timeout.
//   * Cancellation: pass a CancelToken so a blocked acquire returns nullptr
//     when the pipeline is shut down.
//
// Ownership note
// --------------
//   MemoryPool must be held via `std::shared_ptr` (it uses
//   `enable_shared_from_this` internally so the deleter can safely recycle
//   buffers even if the last strong ref to the pool is the deleter itself).
//   Use `MemoryPool<T>::create(capacity)` to construct one.
//
// Non-goals
// ---------
//   * Not lock-free — the mutex simplifies condition-variable signalling and
//     keeps the code small. For audio fan-out hot paths use RingBuffer.
//   * Not NUMA-aware. Nodes that need per-core pools can hold an array of
//     MemoryPool<T> and route by thread id.

#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

#include "rac/graph/cancel_token.hpp"

namespace rac::graph {

template <typename T>
class MemoryPool : public std::enable_shared_from_this<MemoryPool<T>> {
public:
    using Handle  = std::shared_ptr<T>;
    using Factory = std::function<std::unique_ptr<T>()>;

    /// Factory — always prefer this over constructing directly. Returns a
    /// shared_ptr so the pool can hand weak_ptrs to its buffer deleters.
    static std::shared_ptr<MemoryPool<T>> create(size_t capacity) {
        return create(capacity, default_factory);
    }

    static std::shared_ptr<MemoryPool<T>> create(size_t capacity, Factory factory) {
        // Uses the public ctor; private ctor would require a passkey idiom.
        return std::shared_ptr<MemoryPool<T>>(
            new MemoryPool<T>(capacity, std::move(factory)));
    }

    /// Public so clients that don't need the auto-recycle deleter behaviour
    /// (e.g. single-shot tests) can still construct on the stack. In that
    /// case callers must ensure the pool outlives every outstanding handle.
    explicit MemoryPool(size_t capacity)
        : MemoryPool(capacity, default_factory) {}

    MemoryPool(size_t capacity, Factory factory)
        : capacity_(capacity), factory_(std::move(factory)) {
        pool_.reserve(capacity_);
        for (size_t i = 0; i < capacity_; ++i) {
            pool_.emplace_back(factory_());
        }
    }

    ~MemoryPool() = default;

    MemoryPool(const MemoryPool&)            = delete;
    MemoryPool& operator=(const MemoryPool&) = delete;

    /// Block until a buffer is free, or `cancel` fires. Returns nullptr on
    /// cancel.
    Handle acquire(CancelToken* cancel = nullptr) {
        std::unique_lock<std::mutex> lock(mu_);
        while (pool_.empty()) {
            if (cancel && cancel->is_cancelled()) return nullptr;
            // Timed wait so late-arriving cancels are observed within 50ms
            // without requiring the canceller to also notify this cv.
            cv_.wait_for(lock, std::chrono::milliseconds(50));
        }
        return take_locked();
    }

    /// Like `acquire()` but bounded by `timeout`. Returns nullptr on timeout
    /// or cancel.
    Handle acquire_for(std::chrono::milliseconds timeout,
                       CancelToken* cancel = nullptr) {
        std::unique_lock<std::mutex> lock(mu_);
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        while (pool_.empty()) {
            if (cancel && cancel->is_cancelled()) return nullptr;
            if (cv_.wait_until(lock, deadline) == std::cv_status::timeout
                && pool_.empty()) {
                return nullptr;
            }
        }
        return take_locked();
    }

    /// Non-blocking. Returns nullptr if the pool is empty.
    Handle try_acquire() {
        std::lock_guard<std::mutex> lock(mu_);
        if (pool_.empty()) return nullptr;
        return take_locked();
    }

    size_t available() const {
        std::lock_guard<std::mutex> lock(mu_);
        return pool_.size();
    }

    size_t in_flight() const {
        std::lock_guard<std::mutex> lock(mu_);
        return capacity_ - pool_.size();
    }

    size_t capacity() const noexcept { return capacity_; }

private:
    static std::unique_ptr<T> default_factory() {
        return std::make_unique<T>();
    }

    /// Caller holds `mu_`. Pops one buffer off the free list and wraps it in
    /// a shared_ptr whose deleter returns the raw pointer to the pool — or,
    /// if the pool has already been destroyed, deletes it normally.
    Handle take_locked() {
        std::unique_ptr<T> uniq = std::move(pool_.back());
        pool_.pop_back();
        T* raw = uniq.release();

        // weak_from_this() returns an empty weak_ptr if the pool isn't
        // managed by a shared_ptr (e.g. stack-constructed for a test). In
        // that case the deleter lock() below fails and we fall back to a
        // plain delete — buffers leak into the heap instead of back into
        // the pool, which is acceptable for the non-shared case because
        // the pool's own destructor would have freed them anyway.
        std::weak_ptr<MemoryPool<T>> weak_self = this->weak_from_this();
        return Handle(raw, [weak_self](T* p) {
            if (auto self = weak_self.lock()) {
                self->release_raw(p);
            } else {
                delete p;
            }
        });
    }

    void release_raw(T* p) {
        {
            std::lock_guard<std::mutex> lock(mu_);
            pool_.emplace_back(std::unique_ptr<T>(p));
        }
        cv_.notify_one();
    }

    const size_t                    capacity_;
    Factory                         factory_;
    mutable std::mutex              mu_;
    std::condition_variable         cv_;
    std::vector<std::unique_ptr<T>> pool_;
};

}  // namespace rac::graph
