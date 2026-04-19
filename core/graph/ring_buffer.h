// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Lock-free single-producer / single-consumer ring buffer.
//
// Ported from RCLI (src/core/ring_buffer.h) and FastVoice
// (VoiceAI/src/core/ring_buffer.h). Capacity is fixed at construction and
// rounded up to a power of two. The implementation uses acquire/release
// atomics on head/tail, so the producer and consumer each have a single
// cache line they own.
//
// Typical use: one producer thread pushes samples/tokens, one consumer
// thread pops them. For multi-producer/multi-consumer use, wrap with
// StreamEdge (which adds condvar-based blocking).

#ifndef RA_CORE_RING_BUFFER_H
#define RA_CORE_RING_BUFFER_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <type_traits>

namespace ra::core {

template <typename T>
class RingBuffer {
    static_assert(std::is_trivially_copyable_v<T>,
                  "RingBuffer<T>: T must be trivially copyable");

public:
    explicit RingBuffer(std::size_t capacity)
        : capacity_(normalize_capacity(capacity)),
          mask_(capacity_ - 1),
          data_(new T[capacity_]()),
          head_(0),
          tail_(0) {}

    RingBuffer(const RingBuffer&)            = delete;
    RingBuffer& operator=(const RingBuffer&) = delete;
    RingBuffer(RingBuffer&&)                 = delete;
    RingBuffer& operator=(RingBuffer&&)      = delete;
    ~RingBuffer() = default;

    std::size_t capacity() const noexcept { return capacity_; }

    std::size_t size() const noexcept {
        const auto h = head_.load(std::memory_order_acquire);
        const auto t = tail_.load(std::memory_order_acquire);
        return h - t;
    }

    bool empty() const noexcept { return size() == 0; }
    bool full()  const noexcept { return size() == capacity_; }

    // Producer: push one item. Returns false when full.
    bool push(const T& value) noexcept {
        const auto h = head_.load(std::memory_order_relaxed);
        const auto t = tail_.load(std::memory_order_acquire);
        if (h - t == capacity_) return false;
        data_[h & mask_] = value;
        head_.store(h + 1, std::memory_order_release);
        return true;
    }

    // Producer: bulk push up to n items. Returns number written.
    std::size_t push_n(const T* values, std::size_t n) noexcept {
        const auto h = head_.load(std::memory_order_relaxed);
        const auto t = tail_.load(std::memory_order_acquire);
        const auto free_slots = capacity_ - (h - t);
        const auto to_write = (n < free_slots) ? n : free_slots;

        for (std::size_t i = 0; i < to_write; ++i) {
            data_[(h + i) & mask_] = values[i];
        }
        head_.store(h + to_write, std::memory_order_release);
        return to_write;
    }

    // Consumer: pop one item. Returns false when empty.
    bool pop(T& out) noexcept {
        const auto t = tail_.load(std::memory_order_relaxed);
        const auto h = head_.load(std::memory_order_acquire);
        if (h == t) return false;
        out = data_[t & mask_];
        tail_.store(t + 1, std::memory_order_release);
        return true;
    }

    // Consumer: bulk pop up to n items. Returns number read.
    std::size_t pop_n(T* out, std::size_t n) noexcept {
        const auto t = tail_.load(std::memory_order_relaxed);
        const auto h = head_.load(std::memory_order_acquire);
        const auto avail = h - t;
        const auto to_read = (n < avail) ? n : avail;

        for (std::size_t i = 0; i < to_read; ++i) {
            out[i] = data_[(t + i) & mask_];
        }
        tail_.store(t + to_read, std::memory_order_release);
        return to_read;
    }

    // Consumer-side reset. Drops all pending data. Must not be called
    // concurrently with push or pop. Used on barge-in to flush queued PCM.
    void drain() noexcept {
        const auto h = head_.load(std::memory_order_acquire);
        tail_.store(h, std::memory_order_release);
    }

private:
    // Highest power-of-two that fits in a size_t. Any request larger than
    // this would overflow `round_up_pow2` to zero and silently produce a
    // buffer that never holds data.
    static constexpr std::size_t max_power_of_two() noexcept {
        return (std::numeric_limits<std::size_t>::max() >> 1) + 1;
    }

    static std::size_t normalize_capacity(std::size_t n) {
        if (n > max_power_of_two()) {
            throw std::length_error("RingBuffer capacity exceeds size_t range");
        }
        return round_up_pow2(n);
    }

    static constexpr std::size_t round_up_pow2(std::size_t n) noexcept {
        if (n <= 1) return 1;
        --n;
        n |= n >> 1;
        n |= n >> 2;
        n |= n >> 4;
        n |= n >> 8;
        n |= n >> 16;
        if constexpr (sizeof(std::size_t) > 4) {
            n |= n >> 32;
        }
        return n + 1;
    }

    const std::size_t           capacity_;
    const std::size_t           mask_;
    std::unique_ptr<T[]>        data_;

    // Producer writes head_, consumer reads.
    alignas(64) std::atomic<std::uint64_t> head_;
    // Consumer writes tail_, producer reads.
    alignas(64) std::atomic<std::uint64_t> tail_;
};

}  // namespace ra::core

#endif  // RA_CORE_RING_BUFFER_H
