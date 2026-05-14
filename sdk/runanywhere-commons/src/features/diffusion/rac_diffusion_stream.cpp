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
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#endif

namespace {

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

uint64_t next_session_id() {
    static std::atomic<uint64_t> g_counter{0};
    return g_counter.fetch_add(1, std::memory_order_relaxed) + 1;
}

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
        g_slots()[handle] = CallbackSlot{callback, user_data, /*seq=*/0};
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

    const uint64_t id = next_session_id();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        StreamSession& s = g_sessions()[id];
        s.handle = handle;
        s.request_id = parsed.request_id().empty() ? std::string("diffusion-") + std::to_string(id)
                                                   : parsed.request_id();
        s.is_cancelled.store(false, std::memory_order_relaxed);
    }
    *out_session_id = id;

    // TODO(CPP-03 follow-up): kick off the diffusion engine here. The
    // existing rac_diffusion_generate_with_progress_proto() path remains
    // the supported codegen entrypoint; the new stream-callback registry
    // will replace it once SDK migration lands.
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
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    it->second.is_cancelled.store(true, std::memory_order_relaxed);
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
