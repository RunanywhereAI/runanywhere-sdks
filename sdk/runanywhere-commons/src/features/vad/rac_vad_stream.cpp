/**
 * @file rac_vad_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte VAD stream ABI
 *        declared in `rac_vad_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids.
 *
 * MVP scope:
 *   - Callback registration and session create/stop/cancel are fully wired.
 *   - feed_audio_proto forwards Int16 mono PCM bytes to
 *     rac_vad_component_process(), then dispatches a
 *     VAD_STREAM_EVENT_KIND_FRAME event with a VADResult payload via
 *     dispatch_vad_stream_event(). Energy is the RMS of the converted
 *     samples; speech-activity transitions continue to flow through the
 *     existing per-handle proto activity callback registered separately.
 */

#include "rac/features/vad/rac_vad_stream.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "vad_options.pb.h"
#endif

namespace {

struct CallbackSlot {
    rac_vad_stream_proto_callback_fn fn = nullptr;
    void* user_data = nullptr;
    uint64_t seq = 0;
};

struct StreamSession {
    rac_handle_t handle = nullptr;
    std::string request_id;
    std::atomic<bool> is_cancelled{false};
    int32_t sample_rate = 16000;
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

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::vad {
// Forward declaration: implemented later in this same TU. Used by
// rac_vad_stream_feed_audio_proto() to emit FRAME events.
void dispatch_vad_stream_event(rac_handle_t handle, runanywhere::v1::VADStreamEventKind kind,
                               const runanywhere::v1::VADResult* result,
                               const runanywhere::v1::SpeechActivityEvent* activity,
                               const runanywhere::v1::VADStatistics* statistics,
                               const char* error_message, int error_code);
}  // namespace rac::vad
#endif

extern "C" {

rac_result_t rac_vad_set_stream_proto_callback(rac_handle_t handle,
                                               rac_vad_stream_proto_callback_fn callback,
                                               void* user_data) {
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

rac_result_t rac_vad_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_stream_start_proto(rac_handle_t handle, const uint8_t* options_proto_bytes,
                                        size_t options_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (options_proto_size > 0 && options_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)options_proto_bytes;
    (void)options_proto_size;
    *out_session_id = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    runanywhere::v1::VADOptions parsed;
    if (options_proto_size > 0 &&
        !parsed.ParseFromArray(options_proto_bytes, static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const uint64_t id = next_session_id();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        StreamSession& s = g_sessions()[id];
        s.handle = handle;
        s.request_id = "vad-" + std::to_string(id);
        s.is_cancelled.store(false, std::memory_order_relaxed);
        // VADOptions does not carry a sample rate today; default to 16 kHz
        // which matches RAC_VAD_DEFAULT_SAMPLE_RATE / Silero / energy VAD.
        s.sample_rate = 16000;
    }
    *out_session_id = id;
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_vad_stream_feed_audio_proto(uint64_t session_id, const uint8_t* audio_bytes,
                                             size_t audio_size) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (audio_size > 0 && audio_bytes == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;

#if !defined(RAC_HAVE_PROTOBUF)
    (void)audio_bytes;
    (void)audio_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    // Snapshot session state under the lock — release before calling into
    // the VAD component so we don't hold g_mu() across user callbacks.
    // The request_id is stamped onto the dispatched event by
    // dispatch_vad_stream_event() via its own session-table lookup.
    rac_handle_t component_handle = nullptr;
    int32_t sample_rate = 16000;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        if (it->second.is_cancelled.load(std::memory_order_relaxed)) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        component_handle = it->second.handle;
        sample_rate = it->second.sample_rate;
    }
    if (component_handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (audio_size == 0) {
        return RAC_SUCCESS;
    }

    // Convert PCM Int16 mono -> float [-1.0, 1.0]. We accept only complete
    // 16-bit samples; an odd byte count drops the trailing byte. PCM Int16
    // matches what the rest of the C ABI uses (RAC_STT_BYTES_PER_SAMPLE).
    const size_t num_samples = audio_size / sizeof(int16_t);
    if (num_samples == 0) {
        return RAC_SUCCESS;
    }
    const auto* pcm = reinterpret_cast<const int16_t*>(audio_bytes);
    std::vector<float> samples(num_samples);
    double sum_sq = 0.0;
    constexpr float kInt16Scale = 1.0f / 32768.0f;
    for (size_t i = 0; i < num_samples; ++i) {
        const float s = static_cast<float>(pcm[i]) * kInt16Scale;
        samples[i] = s;
        sum_sq += static_cast<double>(s) * static_cast<double>(s);
    }
    const float energy =
        num_samples > 0 ? static_cast<float>(std::sqrt(sum_sq / static_cast<double>(num_samples)))
                        : 0.0f;

    // Forward to the VAD component. Speech-activity transitions still flow
    // through whichever activity callback is registered (energy VAD's
    // internal callback or rac_vad_component_set_activity_proto_callback).
    rac_bool_t is_speech = RAC_FALSE;
    rac_result_t rc =
        rac_vad_component_process(component_handle, samples.data(), samples.size(), &is_speech);
    if (rc != RAC_SUCCESS) {
        runanywhere::v1::VADResult err_payload;
        err_payload.set_is_speech(false);
        err_payload.set_confidence(0.0f);
        err_payload.set_energy(0.0f);
        err_payload.set_duration_ms(0);
        err_payload.set_timestamp_ms(rac_get_current_time_ms());
        err_payload.set_error_code(rc);
        const char* msg = "VAD frame processing failed";
        rac::vad::dispatch_vad_stream_event(component_handle,
                                            runanywhere::v1::VAD_STREAM_EVENT_KIND_ERROR,
                                            /*result=*/nullptr,
                                            /*activity=*/nullptr,
                                            /*statistics=*/nullptr, msg, rc);
        return rc;
    }

    const int32_t duration_ms =
        sample_rate > 0
            ? static_cast<int32_t>(
                  (static_cast<double>(num_samples) / static_cast<double>(sample_rate)) * 1000.0)
            : 0;

    runanywhere::v1::VADResult payload;
    payload.set_is_speech(is_speech == RAC_TRUE);
    payload.set_confidence(is_speech == RAC_TRUE ? 1.0f : 0.0f);
    payload.set_energy(energy);
    payload.set_duration_ms(duration_ms);
    payload.set_timestamp_ms(rac_get_current_time_ms());

    rac::vad::dispatch_vad_stream_event(component_handle,
                                        runanywhere::v1::VAD_STREAM_EVENT_KIND_FRAME, &payload,
                                        /*activity=*/nullptr,
                                        /*statistics=*/nullptr,
                                        /*error_message=*/nullptr,
                                        /*error_code=*/0);
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_vad_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_stream_cancel_proto(uint64_t session_id) {
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
namespace rac::vad {

/**
 * @brief Internal helper invoked by vad_component.cpp's streaming
 *        dispatcher per frame / activity transition / statistics snapshot.
 *
 * Looks up the most recent active session bound to @p handle (if any) and
 * stamps its request_id on the emitted event so downstream consumers can
 * correlate frames. When no session is active the request_id field is left
 * empty; only the per-handle stream callback is required.
 */
void dispatch_vad_stream_event(rac_handle_t handle, runanywhere::v1::VADStreamEventKind kind,
                               const runanywhere::v1::VADResult* result,
                               const runanywhere::v1::SpeechActivityEvent* activity,
                               const runanywhere::v1::VADStatistics* statistics,
                               const char* error_message, int error_code) {
    CallbackSlot slot;
    uint64_t seq = 0;
    std::string request_id;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        slot = it->second;
        seq = ++(it->second.seq);
        for (const auto& [_, session] : g_sessions()) {
            if (session.handle == handle && !session.is_cancelled.load(std::memory_order_relaxed)) {
                request_id = session.request_id;
                break;
            }
        }
    }

    thread_local runanywhere::v1::VADStreamEvent proto_event;
    thread_local std::vector<uint8_t> scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    if (!request_id.empty()) {
        proto_event.set_request_id(request_id);
    }
    proto_event.set_kind(kind);
    if (result) {
        *proto_event.mutable_result() = *result;
    }
    if (activity) {
        *proto_event.mutable_activity() = *activity;
    }
    if (statistics) {
        *proto_event.mutable_statistics() = *statistics;
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
        RAC_LOG_WARNING("vad", "dispatch_vad_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::vad
#endif  // RAC_HAVE_PROTOBUF
