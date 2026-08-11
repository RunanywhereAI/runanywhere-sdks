/**
 * @file rac_stream_registry_internal.h
 * @brief Shared primitives for the per-feature proto-byte stream dispatchers
 *        (llm/stt/tts/diffusion).
 *
 * Internal header (not installed). Each feature's stream TU keeps its OWN
 * per-TU registry statics — the mutex, the per-handle CallbackSlot map, and
 * the per-id session map — because those MUST stay per-feature (feature A's
 * handles must never collide with feature B's in one shared map). Only the
 * stateless / per-instance primitives below are shared:
 *   - CallbackSlot<Fn>   (the per-handle callback record; Fn differs per modality)
 *   - SessionIdAllocator (one instance per TU keeps an independent id sequence)
 *   - InFlightGuard / ShutdownAwareInFlightGuard (quiesce-on-teardown counters)
 *
 * These collapse the byte-identical copies that previously lived inline in
 * rac_{llm,stt,tts,diffusion}_stream.cpp.
 */

#ifndef RAC_FEATURES_COMMON_RAC_STREAM_REGISTRY_INTERNAL_H
#define RAC_FEATURES_COMMON_RAC_STREAM_REGISTRY_INTERNAL_H

#include <atomic>
#include <cstdint>

namespace rac::stream {

/**
 * Per-handle callback record. `Fn` is each modality's
 * rac_<mod>_stream_proto_callback_fn typedef (distinct per feature), so this
 * is a template rather than a concrete struct.
 */
template <typename Fn>
struct CallbackSlot {
    Fn fn = nullptr;
    void* user_data = nullptr;
    uint64_t seq = 0;
};

/**
 * Monotonic session-id allocator. Declare one `static SessionIdAllocator` per
 * TU so each feature keeps an independent id sequence. next() skips 0, which
 * SDK callers treat as the "invalid session" sentinel.
 */
class SessionIdAllocator {
   public:
    uint64_t next() { return counter_.fetch_add(1, std::memory_order_relaxed) + 1; }

   private:
    std::atomic<uint64_t> counter_{0};
};

/**
 * RAII in-flight counter for the quiesce-on-teardown pattern: a destroy/unset
 * path spin-waits on the counter reaching 0 before freeing user_data that an
 * in-flight slot.fn() might still touch. The counter is caller-owned (one
 * `static std::atomic<int>` per TU). Behaviour is identical to the former
 * per-feature *InFlightGuard structs.
 */
class InFlightGuard {
   public:
    explicit InFlightGuard(std::atomic<int>& counter) : counter_(counter) {
        counter_.fetch_add(1, std::memory_order_acq_rel);
    }
    ~InFlightGuard() { counter_.fetch_sub(1, std::memory_order_acq_rel); }
    InFlightGuard(const InFlightGuard&) = delete;
    InFlightGuard& operator=(const InFlightGuard&) = delete;

   private:
    std::atomic<int>& counter_;
};

/**
 * Shutdown-aware variant: closes the TOCTOU race where a new caller acquires
 * the counter mid-quiesce. Checks the shutdown flag, increments, re-checks,
 * and exposes admitted() so an entry point can early-return without
 * dispatching. The caller owns both the counter and the flag (per TU).
 *
 * Use this only where a quiesce path actually sets `shutting_down` (today:
 * diffusion). Pairing it with a flag that is never set just degrades to
 * InFlightGuard plus two extra atomic loads, so the simple guard is preferred
 * elsewhere.
 */
class ShutdownAwareInFlightGuard {
   public:
    ShutdownAwareInFlightGuard(std::atomic<int>& counter, std::atomic<bool>& shutting_down)
        : counter_(counter) {
        if (shutting_down.load(std::memory_order_acquire)) {
            return;
        }
        counter_.fetch_add(1, std::memory_order_acq_rel);
        // Re-check after incrementing to avoid TOCTOU with the quiesce path.
        if (shutting_down.load(std::memory_order_acquire)) {
            counter_.fetch_sub(1, std::memory_order_acq_rel);
            return;
        }
        admitted_ = true;
    }
    ~ShutdownAwareInFlightGuard() {
        if (admitted_) {
            counter_.fetch_sub(1, std::memory_order_acq_rel);
        }
    }
    bool admitted() const { return admitted_; }
    ShutdownAwareInFlightGuard(const ShutdownAwareInFlightGuard&) = delete;
    ShutdownAwareInFlightGuard& operator=(const ShutdownAwareInFlightGuard&) = delete;

   private:
    std::atomic<int>& counter_;
    bool admitted_{false};
};

}  // namespace rac::stream

#endif /* RAC_FEATURES_COMMON_RAC_STREAM_REGISTRY_INTERNAL_H */
