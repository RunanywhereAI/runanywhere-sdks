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

#include "qhexrt_request_cancellation.h"

#include <atomic>
#include <mutex>
#include <string>

#include "qhexrt/qhexrt_c.h"

namespace qhexrt_engine {

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
    RequestCancellation tts_requests;
    RequestCancellation diffusion_requests;
    std::string model_ref;
    std::string scratch_dir;
    // Resolved manifest file (session_open). Used by the diffusion adapter to
    // classify which host-op — LaMa inpaint vs Cosmos3 text-to-image — this
    // session actually serves, so it advertises only that mode.
    std::string manifest_path;
    // Cached diffusion classification: -1 = unresolved, 0 = inpainting,
    // 1 = text-to-image. Lazily derived from manifest_path; deterministic, so a
    // benign race just recomputes the same value.
    std::atomic<int> diffusion_kind{-1};
};

// Acquire the process runtime, load `manifest_path`, create a session.
// Returns nullptr on any failure (runtime refcount left balanced).
Session* session_open(const char* manifest_path);

// Free the session + model and release the process runtime. NULL-safe.
void session_close(Session* s);

}  // namespace qhexrt_engine

#endif  // RUNANYWHERE_QHEXRT_SESSION_H
