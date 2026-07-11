/**
 * @file qhexrt_session.h
 * @brief Shared QHexRT session helper used by every modality adapter.
 *
 * Compiled ONLY in routable builds (RAC_QHEXRT_ENGINE_AVAILABLE=1). Each
 * primitive's vtable `create`/`destroy` opens/closes one of these; the per-
 * modality `generate`/`process`/`transcribe`/`synthesize` then drives the same
 * underlying `qhx_generate`. The process-wide qhx_runtime is refcounted across
 * all open sessions (QHexRT documents the runtime as one-per-process).
 */

#ifndef RUNANYWHERE_QHEXRT_SESSION_H
#define RUNANYWHERE_QHEXRT_SESSION_H

#include <atomic>
#include <mutex>
#include <string>

#include "qhexrt/qhexrt_c.h"

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

// One model + session per service instance. QHexRT sessions are NOT thread-safe.
// Every operation that reads or mutates `sess` must hold operation_mutex for the
// complete operation, including copying session-owned output. Cancellation is
// deliberately independent and remains an atomic, lock-free signal.
struct Session {
    std::mutex operation_mutex;
    qhx_model* model = nullptr;
    qhx_session* sess = nullptr;
    std::atomic<bool> cancel{false};
    RequestCancellation llm_requests;
    RequestCancellation vlm_requests;
    std::string model_ref;
    std::string scratch_dir;
};

// Acquire the process runtime, load `manifest_path`, create a session.
// Returns nullptr on any failure (runtime refcount left balanced).
Session* session_open(const char* manifest_path);

// Free the session + model and release the process runtime. NULL-safe.
void session_close(Session* s);

}  // namespace qhexrt_engine

#endif  // RUNANYWHERE_QHEXRT_SESSION_H
