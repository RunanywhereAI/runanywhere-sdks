/**
 * @file qhexrt_request_cancellation.h
 * @brief Request-scoped cancellation state shared by QHexRT modality adapters.
 */

#ifndef RUNANYWHERE_QHEXRT_REQUEST_CANCELLATION_H
#define RUNANYWHERE_QHEXRT_REQUEST_CANCELLATION_H

#include <atomic>
#include <cstdint>

namespace qhexrt_engine {

// A request-scoped cancellation latch. `cancel_active()` never writes a
// process-wide boolean: it records only the currently announced request id.
// A cancel that races reset/setup is therefore preserved, while the next
// independent request receives a higher id and cannot inherit stale state.
struct RequestCancellation {
    std::atomic<uint64_t> next_id{0};
    std::atomic<uint64_t> active_id{0};
    std::atomic<uint64_t> cancelled_id{0};

    uint64_t begin() {
        const uint64_t id = next_id.fetch_add(1, std::memory_order_acq_rel) + 1;
        active_id.store(id, std::memory_order_release);
        return id;
    }

    void finish(uint64_t id) {
        uint64_t expected = id;
        (void)active_id.compare_exchange_strong(expected, 0, std::memory_order_acq_rel);
    }

    void cancel_active() {
        const uint64_t id = active_id.load(std::memory_order_acquire);
        if (id != 0) {
            cancelled_id.store(id, std::memory_order_release);
        }
    }

    bool is_cancelled(uint64_t id) const {
        return id != 0 && cancelled_id.load(std::memory_order_acquire) == id;
    }
};

}  // namespace qhexrt_engine

#endif  // RUNANYWHERE_QHEXRT_REQUEST_CANCELLATION_H
