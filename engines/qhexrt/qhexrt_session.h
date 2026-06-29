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
#include <string>
#include <vector>

#include "qhexrt/qhexrt_c.h"

namespace qhexrt_engine {

// One model + session per service instance. Sessions are NOT thread-safe, so a
// single Session must not be driven concurrently — the SDK owns one per handle.
struct Session {
    qhx_model* model = nullptr;
    qhx_session* sess = nullptr;
    std::atomic<bool> cancel{false};

    // Model family from the manifest's `model.tokenizer_pre` (e.g. "qwen2",
    // "lfm", "gemma", "default"). Drives chat-template selection in the LLM
    // adapter: these bundles ship no chat template and the runtime decodes the
    // raw `text`, so the engine must wrap the prompt in the family's turn
    // structure or a conversational prompt never forms (the model just
    // continues the text and loops).
    std::string tokenizer_pre;

    // Holds the chat-templated prompt for the lifetime of one qhx_generate call
    // (qhx_inputs.text is a borrowed pointer; it must outlive the call).
    std::string prompt_scratch;

    // Stop strings (family end-of-turn marker + any caller stops) kept alive for
    // the qhx_generate call. qhx_gen_cfg.stop_strings borrows these pointers.
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
};

// Acquire the process runtime, load `manifest_path`, create a session.
// Returns nullptr on any failure (runtime refcount left balanced).
Session* session_open(const char* manifest_path);

// Free the session + model and release the process runtime. NULL-safe.
void session_close(Session* s);

}  // namespace qhexrt_engine

#endif  // RUNANYWHERE_QHEXRT_SESSION_H
