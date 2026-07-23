/**
 * @file rac_diffusion_stream.cpp
 * @brief Lifecycle-owned proto-byte diffusion stream ABI.
 *
 * Registers per-handle callbacks and kicks off generation so SDKs receive
 * STARTED → PROGRESS* → COMPLETED/ERROR events without re-implementing the
 * orchestration loop in Swift/Kotlin/Web.
 */

#include "rac/features/diffusion/rac_diffusion_stream.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_proto_adapters.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

std::atomic<int>& diffusion_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

std::atomic<bool>& diffusion_proto_shutting_down() {
    static std::atomic<bool> flag{false};
    return flag;
}

std::mutex& in_flight_mu() {
    static std::mutex m;
    return m;
}

std::condition_variable& in_flight_cv() {
    static std::condition_variable cv;
    return cv;
}

// Decrement the in-flight counter and wake rac_diffusion_proto_quiesce() when it
// reaches zero, so quiesce can block on a condition_variable instead of a
// core-pegging busy yield-spin. The worker holds one count for its whole
// lifetime, so the transition to zero always runs through here.
void diffusion_in_flight_release() {
    if (diffusion_in_flight().fetch_sub(1, std::memory_order_acq_rel) == 1) {
        std::lock_guard<std::mutex> lock(in_flight_mu());
        in_flight_cv().notify_all();
    }
}

struct StreamSession {
    rac_handle_t handle = nullptr;
    std::string request_id;
    std::atomic<bool> is_cancelled{false};
};

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}

std::unordered_map<rac_handle_t, rac::stream::CallbackSlot<rac_diffusion_stream_proto_callback_fn>>&
g_slots() {
    static std::unordered_map<rac_handle_t,
                              rac::stream::CallbackSlot<rac_diffusion_stream_proto_callback_fn>>
        m;
    return m;
}

std::unordered_map<uint64_t, StreamSession>& g_sessions() {
    static std::unordered_map<uint64_t, StreamSession> m;
    return m;
}

/** At most one active stream session per diffusion handle. */
std::unordered_map<rac_handle_t, uint64_t>& g_active_by_handle() {
    static std::unordered_map<rac_handle_t, uint64_t> m;
    return m;
}

std::atomic<uint64_t>& next_session_id() {
    static std::atomic<uint64_t> id{1};
    return id;
}

/** Clear session bookkeeping. Caller must hold g_mu(). */
void erase_session_locked(uint64_t session_id, rac_handle_t handle) {
    g_sessions().erase(session_id);
    auto it = g_active_by_handle().find(handle);
    if (it != g_active_by_handle().end() && it->second == session_id) {
        g_active_by_handle().erase(it);
    }
}

#if defined(RAC_HAVE_PROTOBUF)
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

void free_diffusion_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    rac_free(const_cast<uint8_t*>(options->input_image_data));
    rac_free(const_cast<uint8_t*>(options->mask_data));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}
#endif

}  // namespace

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::diffusion {

void dispatch_diffusion_stream_event(rac_handle_t handle,
                                     runanywhere::v1::DiffusionStreamEventKind kind,
                                     const runanywhere::v1::DiffusionProgress* progress,
                                     const runanywhere::v1::DiffusionResult* result,
                                     const char* error_message, int error_code);

}  // namespace rac::diffusion
#endif

extern "C" {

rac_result_t rac_diffusion_set_stream_proto_callback(
    rac_handle_t handle, rac_diffusion_stream_proto_callback_fn callback, void* user_data) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = rac::stream::CallbackSlot<rac_diffusion_stream_proto_callback_fn>{
            .fn = callback, .user_data = user_data, .seq = 0};
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

void rac_diffusion_proto_quiesce(void) {
    diffusion_proto_shutting_down().store(true, std::memory_order_release);

    // Cancel any in-flight generations so teardown (component destroy / model
    // swap) does not block for a full 30-60s generation. Snapshot the active
    // handles under g_mu(), mark their sessions cancelled, then route the cancel
    // through the engine outside the lock.
    std::vector<rac_handle_t> active_handles;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        active_handles.reserve(g_active_by_handle().size());
        for (const auto& entry : g_active_by_handle()) {
            auto it = g_sessions().find(entry.second);
            if (it != g_sessions().end()) {
                it->second.is_cancelled.store(true, std::memory_order_release);
            }
            active_handles.push_back(entry.first);
        }
    }
    for (rac_handle_t handle : active_handles) {
        (void)rac_diffusion_cancel(handle);
    }

    // Block until every in-flight worker/dispatch has drained, waking on the
    // in-flight decrement rather than burning a CPU core. The bounded wait is a
    // safety net against a missed notification.
    {
        std::unique_lock<std::mutex> lock(in_flight_mu());
        while (diffusion_in_flight().load(std::memory_order_acquire) > 0) {
            in_flight_cv().wait_for(lock, std::chrono::milliseconds(10));
        }
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
    runanywhere::v1::DiffusionGenerationRequest parsed;
    if (request_proto_size > 0 &&
        !parsed.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!parsed.has_options()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Reject new sessions once rac_diffusion_proto_quiesce() has begun draining
    // (component destroy / model swap): otherwise a worker minted here could call
    // rac_diffusion_generate_with_progress() on an engine the caller is tearing
    // down. Paired with the check→increment→re-check below (the
    // ShutdownAwareInFlightGuard admit protocol) to close the start-vs-quiesce
    // TOCTOU.
    if (diffusion_proto_shutting_down().load(std::memory_order_acquire)) {
        return RAC_ERROR_SERVICE_BUSY;
    }

    const uint64_t session_id = next_session_id().fetch_add(1, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(g_mu());
        if (g_active_by_handle().find(handle) != g_active_by_handle().end()) {
            return RAC_ERROR_SERVICE_BUSY;
        }
        // StreamSession contains an atomic — assign fields in-place (no copy/move).
        StreamSession& session = g_sessions()[session_id];
        session.handle = handle;
        session.request_id = parsed.request_id();
        session.is_cancelled.store(false, std::memory_order_release);
        g_active_by_handle()[handle] = session_id;
    }
    *out_session_id = session_id;

    // Copy request bytes for the worker thread — the caller may free the
    // original buffer as soon as this function returns.
    std::vector<uint8_t> request_copy(request_proto_bytes,
                                      request_proto_bytes + request_proto_size);

    // Cover the whole worker lifetime so rac_diffusion_proto_quiesce() waits
    // for generation to finish, not just individual event dispatches. Increment
    // then re-check the shutdown flag (the ShutdownAwareInFlightGuard admit
    // protocol) so a worker can never be admitted after quiesce observed
    // in_flight == 0 and returned, letting the caller free/swap the engine.
    diffusion_in_flight().fetch_add(1, std::memory_order_acq_rel);
    if (diffusion_proto_shutting_down().load(std::memory_order_acquire)) {
        diffusion_in_flight_release();
        std::lock_guard<std::mutex> lock(g_mu());
        erase_session_locked(session_id, handle);
        *out_session_id = 0;
        return RAC_ERROR_SERVICE_BUSY;
    }
    try {
        std::thread([handle, session_id, request_copy = std::move(request_copy)]() mutable {
            auto in_flight_done =
                std::shared_ptr<void>(nullptr, [](void*) { diffusion_in_flight_release(); });

            runanywhere::v1::DiffusionGenerationRequest request;
            if (!request.ParseFromArray(request_copy.data(),
                                        static_cast<int>(request_copy.size())) ||
                !request.has_options()) {
                rac::diffusion::dispatch_diffusion_stream_event(
                    handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                    "failed to parse DiffusionGenerationRequest",
                    static_cast<int>(RAC_ERROR_DECODING_ERROR));
                std::lock_guard<std::mutex> lock(g_mu());
                erase_session_locked(session_id, handle);
                return;
            }

            // Check liveness BEFORE emitting STARTED so a cancel that raced in
            // before the worker ran (cancel_proto already delivered the terminal
            // event) does not emit a stray STARTED after the terminal event.
            {
                std::lock_guard<std::mutex> lock(g_mu());
                auto it = g_sessions().find(session_id);
                if (it == g_sessions().end() ||
                    it->second.is_cancelled.load(std::memory_order_acquire)) {
                    erase_session_locked(session_id, handle);
                    return;
                }
            }

            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_STARTED, nullptr, nullptr,
                nullptr, 0);

            rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
            if (!rac::foundation::rac_diffusion_options_from_proto(request.options(), &options)) {
                rac::diffusion::dispatch_diffusion_stream_event(
                    handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                    "failed to convert DiffusionGenerationOptions",
                    static_cast<int>(RAC_ERROR_DECODING_ERROR));
                std::lock_guard<std::mutex> lock(g_mu());
                erase_session_locked(session_id, handle);
                return;
            }

            struct ProgressCtx {
                rac_handle_t handle;
                uint64_t session_id;
            } progress_ctx{handle, session_id};

            rac_diffusion_result_t raw = {};
            const rac_result_t rc = rac_diffusion_generate_with_progress(
                handle, &options,
                [](const rac_diffusion_progress_t* progress, void* user_data) -> rac_bool_t {
                    auto* ctx = static_cast<ProgressCtx*>(user_data);
                    if (!ctx || !progress)
                        return RAC_TRUE;
                    {
                        std::lock_guard<std::mutex> lock(g_mu());
                        auto it = g_sessions().find(ctx->session_id);
                        if (it == g_sessions().end() ||
                            it->second.is_cancelled.load(std::memory_order_acquire)) {
                            return RAC_FALSE;  // cancel
                        }
                    }
                    runanywhere::v1::DiffusionProgress proto_progress;
                    if (rac::foundation::rac_diffusion_progress_to_proto(progress, &proto_progress)) {
                        rac::diffusion::dispatch_diffusion_stream_event(
                            ctx->handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_PROGRESS,
                            &proto_progress, nullptr, nullptr, 0);
                    }
                    return RAC_TRUE;
                },
                &progress_ctx, &raw);

            free_diffusion_options(&options);

            {
                std::lock_guard<std::mutex> lock(g_mu());
                auto it = g_sessions().find(session_id);
                if (it == g_sessions().end() ||
                    it->second.is_cancelled.load(std::memory_order_acquire)) {
                    if (rc == RAC_SUCCESS)
                        rac_diffusion_result_free(&raw);
                    erase_session_locked(session_id, handle);
                    return;
                }
            }

            if (rc != RAC_SUCCESS) {
                rac::diffusion::dispatch_diffusion_stream_event(
                    handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                    rac_error_message(rc), static_cast<int>(rc));
                std::lock_guard<std::mutex> lock(g_mu());
                erase_session_locked(session_id, handle);
                return;
            }

            runanywhere::v1::DiffusionResult result;
            if (!rac::foundation::rac_diffusion_result_to_proto(&raw, &result)) {
                rac_diffusion_result_free(&raw);
                rac::diffusion::dispatch_diffusion_stream_event(
                    handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                    "failed to encode DiffusionResult",
                    static_cast<int>(RAC_ERROR_ENCODING_ERROR));
                std::lock_guard<std::mutex> lock(g_mu());
                erase_session_locked(session_id, handle);
                return;
            }
            rac_diffusion_result_free(&raw);
            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_COMPLETED, nullptr, &result,
                nullptr, 0);
            std::lock_guard<std::mutex> lock(g_mu());
            erase_session_locked(session_id, handle);
        }).detach();
    } catch (...) {
        diffusion_in_flight_release();
        std::lock_guard<std::mutex> lock(g_mu());
        erase_session_locked(session_id, handle);
        *out_session_id = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
#endif
}

rac_result_t rac_diffusion_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    if (g_sessions().find(session_id) == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    // Drain semantics: leave the session and its g_active_by_handle entry intact
    // so the worker runs the in-flight generation to completion, delivers the
    // terminal COMPLETED event, and clears bookkeeping via erase_session_locked.
    // Pre-erasing here would strand the handle as SERVICE_BUSY and suppress the
    // COMPLETED event. Use rac_diffusion_stream_cancel_proto for immediate
    // teardown that frees the handle now.
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_handle_t handle = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        it->second.is_cancelled.store(true, std::memory_order_release);
        handle = it->second.handle;
        // Clear g_active_by_handle synchronously (erase_session_locked, not a
        // bare g_sessions().erase) so the handle is immediately free for a new
        // stream. Once the session is gone the worker's checkpoints bail without
        // emitting a second terminal event.
        erase_session_locked(session_id, handle);
    }
    if (handle) {
        (void)rac_diffusion_cancel(handle);
#if defined(RAC_HAVE_PROTOBUF)
        // Deliver a terminal event so the SDK stream terminates instead of
        // hanging waiting for a COMPLETED/ERROR the (now-erased) worker will
        // never dispatch.
        rac::diffusion::dispatch_diffusion_stream_event(
            handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
            "diffusion stream cancelled", static_cast<int>(RAC_ERROR_CANCELLED));
#endif
    }
    return RAC_SUCCESS;
}

}  // extern "C"

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::diffusion {

void dispatch_diffusion_stream_event(rac_handle_t handle,
                                     runanywhere::v1::DiffusionStreamEventKind kind,
                                     const runanywhere::v1::DiffusionProgress* progress,
                                     const runanywhere::v1::DiffusionResult* result,
                                     const char* error_message, int error_code) {
    rac::stream::ShutdownAwareInFlightGuard in_flight_guard(diffusion_in_flight(),
                                                            diffusion_proto_shutting_down());
    if (!in_flight_guard.admitted()) {
        return;
    }
    rac::stream::CallbackSlot<rac_diffusion_stream_proto_callback_fn> slot;
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
