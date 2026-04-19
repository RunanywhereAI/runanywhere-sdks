// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Fixed-size object pool for audio frames and token buffers.
//
// Ported from RCLI (src/core/memory_pool.h) and FastVoice
// (VoiceAI/src/core/memory_pool.h). Allocates N blocks of fixed size up
// front; acquire()/release() return/accept pointers from the pool. When
// exhausted, acquire() returns nullptr — callers either fall back to
// heap alloc or drop the frame (policy-dependent).
//
// Pool is thread-safe via a free-list guarded by a lightweight spinlock.

#ifndef RA_CORE_MEMORY_POOL_H
#define RA_CORE_MEMORY_POOL_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <new>
#include <vector>

#if defined(_WIN32)
#  include <malloc.h>  // _aligned_malloc / _aligned_free
#endif

namespace ra::core {

// A pool of N blocks, each `block_bytes` in size. Alignment defaults to 64
// bytes (cache line) for audio pipelines; override via `alignment`.
class MemoryPool {
public:
    MemoryPool(std::size_t block_bytes,
               std::size_t num_blocks,
               std::size_t alignment = 64)
        : block_bytes_(block_bytes),
          num_blocks_(num_blocks),
          alignment_(alignment) {
        // posix_memalign requires alignment to be a power of two and at
        // least sizeof(void*). Reject anything else up front so we never
        // populate the free list with invalid addresses.
        if (alignment_ < sizeof(void*) ||
            (alignment_ & (alignment_ - 1)) != 0) {
            return;  // storage_ stays null, free_list_ stays empty.
        }

        const auto stride = (block_bytes_ + alignment_ - 1) & ~(alignment_ - 1);
        storage_size_ = stride * num_blocks_;

#if defined(_WIN32)
        storage_ = static_cast<std::uint8_t*>(
            _aligned_malloc(storage_size_, alignment_));
#else
        if (::posix_memalign(reinterpret_cast<void**>(&storage_),
                             alignment_, storage_size_) != 0) {
            storage_ = nullptr;
        }
#endif

        // If allocation failed, leave the pool empty. acquire() returns
        // nullptr and callers can fall back to heap or drop the frame —
        // rather than populating the free list with garbage (null + offset)
        // pointers.
        if (!storage_) {
            storage_size_ = 0;
            return;
        }

        free_list_.reserve(num_blocks_);
        for (std::size_t i = 0; i < num_blocks_; ++i) {
            free_list_.push_back(storage_ + i * stride);
        }
    }

    ~MemoryPool() {
#if defined(_WIN32)
        _aligned_free(storage_);
#else
        std::free(storage_);
#endif
    }

    MemoryPool(const MemoryPool&)            = delete;
    MemoryPool& operator=(const MemoryPool&) = delete;
    MemoryPool(MemoryPool&&)                 = delete;
    MemoryPool& operator=(MemoryPool&&)      = delete;

    std::size_t block_bytes() const noexcept { return block_bytes_; }
    std::size_t capacity()    const noexcept { return num_blocks_; }
    std::size_t available()   const noexcept {
        SpinGuard g(lock_);
        return free_list_.size();
    }

    // Returns a pointer to a free block, or nullptr when the pool is empty.
    std::uint8_t* acquire() noexcept {
        SpinGuard g(lock_);
        if (free_list_.empty()) return nullptr;
        auto* p = free_list_.back();
        free_list_.pop_back();
        return p;
    }

    // Returns a block to the pool. The caller must guarantee the pointer
    // came from this pool's acquire(); otherwise behavior is undefined.
    void release(std::uint8_t* block) noexcept {
        if (!block) return;
        SpinGuard g(lock_);
        free_list_.push_back(block);
    }

private:
    // A tiny spinlock — the critical section is exactly two vector ops, so
    // a mutex would be pure overhead at audio frame rates.
    class SpinGuard {
    public:
        explicit SpinGuard(std::atomic_flag& lock) noexcept : lock_(lock) {
            while (lock_.test_and_set(std::memory_order_acquire)) {
                // spin — no yield: we're inside a microsecond-scale region.
            }
        }
        ~SpinGuard() noexcept { lock_.clear(std::memory_order_release); }

    private:
        std::atomic_flag& lock_;
    };

    const std::size_t  block_bytes_;
    const std::size_t  num_blocks_;
    const std::size_t  alignment_;
    std::size_t        storage_size_ = 0;
    std::uint8_t*      storage_      = nullptr;

    mutable std::atomic_flag          lock_ = ATOMIC_FLAG_INIT;
    std::vector<std::uint8_t*>        free_list_;
};

// RAII wrapper for pool-owned blocks. The pool must outlive every Block
// handed out.
class PooledBlock {
public:
    PooledBlock(MemoryPool* pool, std::uint8_t* ptr) noexcept
        : pool_(pool), ptr_(ptr) {}

    PooledBlock(PooledBlock&& other) noexcept
        : pool_(other.pool_), ptr_(other.ptr_) {
        other.ptr_ = nullptr;
    }

    PooledBlock& operator=(PooledBlock&& other) noexcept {
        if (this != &other) {
            reset();
            pool_ = other.pool_;
            ptr_  = other.ptr_;
            other.ptr_ = nullptr;
        }
        return *this;
    }

    PooledBlock(const PooledBlock&)            = delete;
    PooledBlock& operator=(const PooledBlock&) = delete;

    ~PooledBlock() { reset(); }

    std::uint8_t* get() const noexcept { return ptr_; }
    explicit operator bool() const noexcept { return ptr_ != nullptr; }

    void reset() noexcept {
        if (ptr_ && pool_) pool_->release(ptr_);
        ptr_ = nullptr;
    }

private:
    MemoryPool*   pool_ = nullptr;
    std::uint8_t* ptr_  = nullptr;
};

}  // namespace ra::core

#endif  // RA_CORE_MEMORY_POOL_H
