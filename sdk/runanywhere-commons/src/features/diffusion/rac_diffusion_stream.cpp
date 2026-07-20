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
#include <cstdint>
#include <cstring>
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

std::atomic<uint64_t>& next_session_id() {
    static std::atomic<uint64_t> id{1};
    return id;
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
    runanywhere::v1::DiffusionGenerationRequest parsed;
    if (request_proto_size > 0 &&
        !parsed.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!parsed.has_options()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const uint64_t session_id = next_session_id().fetch_add(1, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(g_mu());
        // StreamSession contains an atomic — assign fields in-place (no copy/move).
        StreamSession& session = g_sessions()[session_id];
        session.handle = handle;
        session.request_id = parsed.request_id();
        session.is_cancelled.store(false, std::memory_order_release);
    }
    *out_session_id = session_id;

    // Copy request bytes for the worker thread — the caller may free the
    // original buffer as soon as this function returns.
    std::vector<uint8_t> request_copy(request_proto_bytes,
                                      request_proto_bytes + request_proto_size);

    std::thread([handle, session_id, request_copy = std::move(request_copy)]() mutable {
        runanywhere::v1::DiffusionGenerationRequest request;
        if (!request.ParseFromArray(request_copy.data(), static_cast<int>(request_copy.size())) ||
            !request.has_options()) {
            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                "failed to parse DiffusionGenerationRequest",
                static_cast<int>(RAC_ERROR_DECODING_ERROR));
            std::lock_guard<std::mutex> lock(g_mu());
            g_sessions().erase(session_id);
            return;
        }

        rac::diffusion::dispatch_diffusion_stream_event(
            handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_STARTED, nullptr, nullptr, nullptr,
            0);

        {
            std::lock_guard<std::mutex> lock(g_mu());
            auto it = g_sessions().find(session_id);
            if (it == g_sessions().end() ||
                it->second.is_cancelled.load(std::memory_order_acquire)) {
                g_sessions().erase(session_id);
                return;
            }
        }

        rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
        if (!rac::foundation::rac_diffusion_options_from_proto(request.options(), &options)) {
            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                "failed to convert DiffusionGenerationOptions",
                static_cast<int>(RAC_ERROR_DECODING_ERROR));
            std::lock_guard<std::mutex> lock(g_mu());
            g_sessions().erase(session_id);
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
                g_sessions().erase(session_id);
                return;
            }
        }

        if (rc != RAC_SUCCESS) {
            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                rac_error_message(rc), static_cast<int>(rc));
            std::lock_guard<std::mutex> lock(g_mu());
            g_sessions().erase(session_id);
            return;
        }

        runanywhere::v1::DiffusionResult result;
        if (!rac::foundation::rac_diffusion_result_to_proto(&raw, &result)) {
            rac_diffusion_result_free(&raw);
            rac::diffusion::dispatch_diffusion_stream_event(
                handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
                "failed to encode DiffusionResult", static_cast<int>(RAC_ERROR_ENCODING_ERROR));
            std::lock_guard<std::mutex> lock(g_mu());
            g_sessions().erase(session_id);
            return;
        }
        rac_diffusion_result_free(&raw);
        rac::diffusion::dispatch_diffusion_stream_event(
            handle, runanywhere::v1::DIFFUSION_STREAM_EVENT_KIND_COMPLETED, nullptr, &result,
            nullptr, 0);
        std::lock_guard<std::mutex> lock(g_mu());
        g_sessions().erase(session_id);
    }).detach();

    return RAC_SUCCESS;
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
    rac_handle_t handle = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        it->second.is_cancelled.store(true, std::memory_order_release);
        handle = it->second.handle;
        g_sessions().erase(it);
    }
    if (handle) {
        (void)rac_diffusion_cancel(handle);
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
