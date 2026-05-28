/**
 * @file rac_diffusion_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte diffusion stream
 *        ABI declared in `rac_diffusion_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids.
 *
 * MVP scope:
 *   - Callback registration and session create/stop/cancel are fully wired.
 *   - The diffusion engine emits progress/completed events via
 *     `dispatch_diffusion_stream_event()` once
 *     `rac_diffusion_proto_abi.cpp` is taught to use it (TODO CPP-03
 *     follow-up).
 *   - start_proto today seeds a session — actual generation kickoff still
 *     flows through the existing `rac_diffusion_generate_with_progress_proto`
 *     ABI; SDKs can already register stream callbacks alongside that path.
 */

#include "rac/features/diffusion/rac_diffusion_stream.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#endif

namespace {

// pass2-syn-001-followup-diffusion: lift the voice_agent in_flight quiesce
// pattern to the diffusion proto-byte dispatcher. See rac_llm_stream.cpp
// and rac_vlm_proto_abi.cpp for the canonical reference; this guards
// dispatch_diffusion_stream_event so destroy/teardown can spin-wait until
// any in-flight slot.fn() returns before freeing user_data.
//
// pass3-syn-089 (commons-101): complete the voice_agent pattern by adding
// an is_shutting_down barrier (voice_agent.cpp:569 / 1212-1221). Without it
// a new caller could acquire the in_flight counter mid-quiesce and extend
// the spin-wait indefinitely (and worse, dispatch into a freed engine).
// DiffusionInFlightGuard now performs the canonical TOCTOU-safe sequence:
// check flag, increment counter, re-check flag, and exposes admitted() so
// entry points can early-return without dispatching.
std::atomic<int>& diffusion_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

std::atomic<bool>& diffusion_proto_shutting_down() {
    static std::atomic<bool> flag{false};
    return flag;
}

struct DiffusionInFlightGuard {
    DiffusionInFlightGuard() {
        if (diffusion_proto_shutting_down().load(std::memory_order_acquire)) {
            return;
        }
        diffusion_in_flight().fetch_add(1, std::memory_order_acq_rel);
        // Re-check after incrementing to avoid TOCTOU with
        // rac_diffusion_proto_quiesce().
        if (diffusion_proto_shutting_down().load(std::memory_order_acquire)) {
            diffusion_in_flight().fetch_sub(1, std::memory_order_acq_rel);
            return;
        }
        admitted_ = true;
    }
    ~DiffusionInFlightGuard() {
        if (admitted_) {
            diffusion_in_flight().fetch_sub(1, std::memory_order_acq_rel);
        }
    }
    bool admitted() const { return admitted_; }
    DiffusionInFlightGuard(const DiffusionInFlightGuard&) = delete;
    DiffusionInFlightGuard& operator=(const DiffusionInFlightGuard&) = delete;

   private:
    bool admitted_{false};
};

struct CallbackSlot {
    rac_diffusion_stream_proto_callback_fn fn = nullptr;
    void* user_data = nullptr;
    uint64_t seq = 0;
};

struct StreamSession {
    rac_handle_t handle = nullptr;
    std::string request_id;
    std::atomic<bool> is_cancelled{false};
};

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}

std::unordered_map<rac_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_handle_t, CallbackSlot> m;
    return m;
}

std::unordered_map<uint64_t, StreamSession>& g_sessions() {
    static std::unordered_map<uint64_t, StreamSession> m;
    return m;
}

// commons-features-other-003: the previous next_session_id() helper was
// inlined into rac_diffusion_stream_start_proto, but that entry point now
// returns RAC_ERROR_NOT_IMPLEMENTED until the diffusion engine kickoff is
// wired into dispatch_diffusion_stream_event(). The session id allocator
// will be reintroduced in lockstep with that wiring; keeping it removed
// today avoids an unused-function lint and clarifies that no live session
// ids are minted on this code path.

#if defined(RAC_HAVE_PROTOBUF)
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}
#endif

}  // namespace

extern "C" {

rac_result_t rac_diffusion_set_stream_proto_callback(
    rac_handle_t handle, rac_diffusion_stream_proto_callback_fn callback, void* user_data) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = CallbackSlot{.fn = callback, .user_data = user_data, .seq = 0};
    }
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

// pass2-syn-001-followup-diffusion: public quiesce helper. Mirrors
// rac_vlm_proto_quiesce / rac_llm_proto_quiesce. Spin-waits until every
// in-flight dispatch_diffusion_stream_event invocation has returned. Callers
// freeing user_data registered via rac_diffusion_set_stream_proto_callback,
// or tearing down the diffusion component, MUST call this after the unset to
// avoid a use-after-free in the dispatch thread.
//
// pass3-syn-089 (commons-101): set the is_shutting_down barrier FIRST so any
// caller that tries to enter the dispatcher after quiesce begins is rejected
// by DiffusionInFlightGuard, then spin-wait until currently-in-flight calls
// drain. Mirrors rac_vlm_proto_quiesce / voice_agent.cpp:569-592.
//
// Diffusion-specific divergence from VLM: diffusion_component.cpp calls this
// quiesce both at destroy AND on every model swap via load_model (see
// diffusion_component.cpp:369). To keep model-swap reuse working, clear the
// barrier after the drain completes. The barrier+drain window is still
// sufficient to close the TOCTOU race because any dispatcher entry that
// observed the false→true transition (or was about to) has either been
// rejected (admitted_=false) or drained (counter decremented). VLM does not
// need this clear because it only quiesces at destroy.
void rac_diffusion_proto_quiesce(void) {
    diffusion_proto_shutting_down().store(true, std::memory_order_release);
    while (diffusion_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
    diffusion_proto_shutting_down().store(false, std::memory_order_release);
}

rac_result_t rac_diffusion_stream_start_proto(rac_handle_t handle,
                                              const uint8_t* request_proto_bytes,
                                              size_t request_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (request_proto_size > 0 && request_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    *out_session_id = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    // Validate the request bytes early so callers still get RAC_ERROR_DECODING_ERROR
    // for malformed inputs even though the engine kickoff is not yet wired.
    runanywhere::v1::DiffusionGenerationRequest parsed;
    if (request_proto_size > 0 &&
        !parsed.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    (void)parsed;

    // CPP-03 follow-up: until the diffusion engine kickoff is wired into
    // dispatch_diffusion_stream_event(), this entrypoint cannot honour the
    // contract documented in rac_diffusion_stream.h ("Session started"
    // implies STARTED/PROGRESS/COMPLETED/ERROR will be dispatched). The
    // header explicitly reserves RAC_ERROR_NOT_IMPLEMENTED for this stub
    // state, so we return that instead of RAC_SUCCESS to prevent SDKs from
    // waiting forever on a session that will never emit a terminal event.
    // The supported codegen entrypoint remains
    // rac_diffusion_generate_with_progress_proto(); SDKs should fall back
    // to it until the kickoff lands.
    *out_session_id = 0;
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_diffusion_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    // commons-027: use release ordering so any writes the cancelling thread
    // made before the store (e.g. draining session state) are visible to a
    // consumer on another core that observes is_cancelled == true. Mirrors
    // tool_calling_session.cpp:805/883 (cancel_requested.store release) and
    // rac_llm_stream.cpp / rag_pipeline_graph.cpp. Readers must pair with
    // memory_order_acquire on the load.
    it->second.is_cancelled.store(true, std::memory_order_release);
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

}  // extern "C"

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::diffusion {

/**
 * @brief Internal helper invoked by the diffusion proto ABI / engine to
 *        emit progress / intermediate-image / completion / error events.
 */
void dispatch_diffusion_stream_event(rac_handle_t handle,
                                     runanywhere::v1::DiffusionStreamEventKind kind,
                                     const runanywhere::v1::DiffusionProgress* progress,
                                     const runanywhere::v1::DiffusionResult* result,
                                     const char* error_message, int error_code) {
    // pass2-syn-001-followup-diffusion: hold the InFlightGuard across the
    // whole dispatch so rac_diffusion_proto_quiesce() can spin-wait on the
    // counter before user_data is freed by a concurrent teardown thread.
    // pass3-syn-089 (commons-101): if the proto dispatcher is shutting down,
    // the guard refuses admission and we must skip the slot lookup + callback
    // invocation entirely — slot.fn / user_data may already be freed.
    DiffusionInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return;
    }
    CallbackSlot slot;
    uint64_t seq = 0;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        slot = it->second;
        seq = ++(it->second.seq);
    }

    thread_local runanywhere::v1::DiffusionStreamEvent proto_event;
    thread_local std::vector<uint8_t> scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    proto_event.set_kind(kind);
    if (progress) {
        *proto_event.mutable_progress() = *progress;
    }
    if (result) {
        *proto_event.mutable_result() = *result;
    }
    if (error_message && error_message[0] != '\0') {
        proto_event.set_error_message(error_message);
    }
    if (error_code != 0) {
        proto_event.set_error_code(error_code);
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed)
        scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("diffusion", "dispatch_diffusion_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::diffusion
#endif  // RAC_HAVE_PROTOBUF
