/**
 * @file rac_tts_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte TTS stream ABI
 *        declared in `rac_tts_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids.
 *
 * MVP scope:
 *   - Callback registration and session create/stop/cancel are fully wired.
 *   - The streaming engine emits chunks via `dispatch_tts_stream_event()`
 *     once the synthesis backend is wired (TODO CPP-03 follow-up).
 *   - start_proto today seeds a session; the SDK side can register
 *     callbacks and walk the session lifecycle. Audio chunk emission is
 *     stubbed pending tts_component integration.
 */

#include "rac/features/tts/rac_tts_stream.h"

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
#include "tts_options.pb.h"
#endif

namespace {

// pass2-syn-001-followup-tts: lift the voice_agent in_flight quiesce pattern
// to the TTS proto-byte dispatcher. See rac_llm_stream.cpp and
// rac_vlm_proto_abi.cpp for the canonical reference; this guards
// dispatch_tts_stream_event so destroy/teardown can spin-wait until any
// in-flight slot.fn() returns before freeing user_data.
std::atomic<int>& tts_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

struct TtsInFlightGuard {
    TtsInFlightGuard() { tts_in_flight().fetch_add(1, std::memory_order_acq_rel); }
    ~TtsInFlightGuard() { tts_in_flight().fetch_sub(1, std::memory_order_acq_rel); }
    TtsInFlightGuard(const TtsInFlightGuard&) = delete;
    TtsInFlightGuard& operator=(const TtsInFlightGuard&) = delete;
};

struct CallbackSlot {
    rac_tts_stream_proto_callback_fn fn = nullptr;
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

rac_result_t rac_tts_set_stream_proto_callback(rac_handle_t handle,
                                               rac_tts_stream_proto_callback_fn callback,
                                               void* user_data) {
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

rac_result_t rac_tts_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

// pass2-syn-001-followup-tts: public quiesce helper. Mirrors
// rac_vlm_proto_quiesce / rac_llm_proto_quiesce. Spin-waits until every
// in-flight dispatch_tts_stream_event invocation has returned. Callers
// freeing user_data registered via rac_tts_set_stream_proto_callback, or
// tearing down the TTS component, MUST call this after the unset to avoid
// a use-after-free in the dispatch thread.
void rac_tts_proto_quiesce(void) {
    while (tts_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
}

rac_result_t rac_tts_stream_start_proto(rac_handle_t handle, const uint8_t* request_proto_bytes,
                                        size_t request_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (request_proto_size > 0 && request_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_session_id = 0;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    runanywhere::v1::TTSSynthesisRequest parsed;
    if (request_proto_size > 0 &&
        !parsed.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    // Per-handle TTS streaming is not yet wired to rac_tts_component's
    // synthesize_stream loop. Until the backend is wired, fail explicitly
    // with NOT_IMPLEMENTED rather than returning SUCCESS for a stub that
    // would leave callers hanging on stream callbacks that never fire.
    // The lifecycle-owned TTS stream path in
    // rac_nonllm_lifecycle_proto_abi.cpp already emits STARTED/AUDIO_CHUNK/
    // COMPLETED via synthesize_stream and remains the supported route.
    // Header rac_tts_stream.h documents this error code for the unwired
    // backend case.
    return RAC_ERROR_NOT_IMPLEMENTED;
#endif
}

rac_result_t rac_tts_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

rac_result_t rac_tts_stream_cancel_proto(uint64_t session_id) {
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
namespace rac::tts {

/**
 * @brief Internal helper invoked by tts_component.cpp's streaming
 *        dispatcher per audio chunk / phoneme / completion.
 */
void dispatch_tts_stream_event(rac_handle_t handle, runanywhere::v1::TTSStreamEventKind kind,
                               const runanywhere::v1::TTSOutput* output,
                               const runanywhere::v1::TTSPhonemeTimestamp* phoneme,
                               const runanywhere::v1::TTSSpeakResult* speak_result,
                               const char* error_message, int error_code) {
    // pass2-syn-001-followup-tts: hold the InFlightGuard across the whole
    // dispatch so rac_tts_proto_quiesce() can spin-wait on the counter
    // before user_data is freed by a concurrent teardown thread.
    TtsInFlightGuard in_flight_guard;
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

    thread_local runanywhere::v1::TTSStreamEvent proto_event;
    thread_local std::vector<uint8_t> scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    proto_event.set_kind(kind);
    if (output) {
        *proto_event.mutable_output() = *output;
    }
    if (phoneme) {
        *proto_event.mutable_phoneme() = *phoneme;
    }
    if (speak_result) {
        *proto_event.mutable_speak_result() = *speak_result;
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
        RAC_LOG_WARNING("tts", "dispatch_tts_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::tts
#endif  // RAC_HAVE_PROTOBUF
