/**
 * @file voice_agent_feed_abi.cpp
 * @brief Streaming audio-ingress voice-agent C ABI —
 *        `rac_voice_agent_feed_audio_proto`.
 *
 * The C core owns no microphone (see the "Audio-Ingress Contract" in
 * rac_voice_agent.h). Platform SDKs capture raw mic frames and push them
 * here continuously; this TU performs energy-based utterance segmentation
 * in-core and, once an utterance closes, runs the shared
 * VAD -> STT -> LLM -> TTS pipeline (`d7_process_utterance`). The
 * synthesized reply is returned inline as a `VoiceAgentResult` so the SDK
 * driver collapses to "capture -> feed -> play", while the per-stage
 * VoiceEvents still fan out through the registered proto callback.
 *
 * PCM contract: 16 kHz mono signed-16-bit little-endian (the format every
 * SDK's AudioCaptureManager already produces).
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

#include "voice_agent_internal.h"
#include "voice_agent_internal_helpers.h"

#if defined(RAC_HAVE_PROTOBUF)

namespace {

// Energy-VAD / endpointing constants. Ported verbatim from the Swift and
// Kotlin VoiceAgentMicDriver segmenters so on-device behavior is unchanged
// now that segmentation lives in one place.
constexpr int kSampleRateHz = 16000;
constexpr int kBytesPerSample = 2;
constexpr int kFrameMs = 100;
constexpr size_t kFrameBytes =
    static_cast<size_t>(kSampleRateHz * kFrameMs / 1000) * kBytesPerSample;  // 3200 bytes
constexpr float kSpeechRmsThreshold = 0.015f;
constexpr float kSpeechFloorMultiplier = 2.2f;
constexpr float kNoiseFloorRise = 0.05f;
constexpr int kEndOfUtteranceSilenceMs = 800;
constexpr int kMinSpeechMs = 300;
constexpr int kMaxUtteranceMs = 15000;
constexpr size_t kPreRollFrames = 3;

// Normalized RMS of one PCM16 frame (matches the SDK drivers: divide by
// Int16.max so the threshold constants carry over unchanged).
float frame_rms(const uint8_t* data, size_t bytes) {
    const size_t samples = bytes / kBytesPerSample;
    if (samples == 0)
        return 0.0f;
    const int16_t* pcm = reinterpret_cast<const int16_t*>(data);
    double sum = 0.0;
    for (size_t i = 0; i < samples; ++i) {
        const double sample = static_cast<double>(pcm[i]);
        sum += sample * sample;
    }
    return static_cast<float>(std::sqrt(sum / static_cast<double>(samples)) / 32767.0);
}

// Accumulate fed audio into fixed analysis frames and run energy endpointing.
// Returns true and moves the completed utterance into @p out_utterance when an
// utterance closes this call (silence tail or max-duration cap). At most one
// utterance is reported per call; any buffered backlog is dropped so the
// device's own TTS playout is not folded into the next turn (mirrors the SDK's
// former discard-pending-chunks behavior). The adaptive noise floor persists
// across turns; only transient state resets.
bool feed_segment(rac_voice_agent_feed_state& s, const void* data, size_t size, bool is_final,
                  std::string* out_utterance) {
    if (data && size > 0) {
        const uint8_t* bytes = static_cast<const uint8_t*>(data);
        s.frame_accum.insert(s.frame_accum.end(), bytes, bytes + size);
    }

    bool completed = false;
    while (s.frame_accum.size() >= kFrameBytes) {
        std::vector<uint8_t> frame(s.frame_accum.begin(), s.frame_accum.begin() + kFrameBytes);
        s.frame_accum.erase(s.frame_accum.begin(), s.frame_accum.begin() + kFrameBytes);

        const float level = frame_rms(frame.data(), frame.size());
        const float threshold =
            std::max(kSpeechRmsThreshold, s.noise_floor * kSpeechFloorMultiplier);
        const bool is_speech = level >= threshold;
        // Only adapt the floor while idle (between utterances). Adapting
        // mid-utterance lets inter-word pauses inflate the floor and lock out
        // the next turn. Drop instantly to any quieter ambient; creep up slowly
        // otherwise.
        if (!s.in_speech) {
            if (level < s.noise_floor) {
                s.noise_floor = level;
            } else if (!is_speech) {
                s.noise_floor += (level - s.noise_floor) * kNoiseFloorRise;
            }
        }

        if (!s.in_speech) {
            s.pre_roll.push_back(std::move(frame));
            if (s.pre_roll.size() > kPreRollFrames)
                s.pre_roll.pop_front();
            if (is_speech) {
                s.in_speech = true;
                s.speech_ms = kFrameMs;
                s.silence_ms = 0;
                s.utterance.clear();
                for (const auto& buffered : s.pre_roll)
                    s.utterance.append(reinterpret_cast<const char*>(buffered.data()),
                                       buffered.size());
                s.pre_roll.clear();
            }
            continue;
        }

        s.utterance.append(reinterpret_cast<const char*>(frame.data()), frame.size());
        if (is_speech) {
            s.speech_ms += kFrameMs;
            s.silence_ms = 0;
        } else {
            s.silence_ms += kFrameMs;
        }

        const int utterance_ms = static_cast<int>((s.utterance.size() / kBytesPerSample) * 1000 /
                                                  kSampleRateHz);
        if (s.silence_ms >= kEndOfUtteranceSilenceMs || utterance_ms >= kMaxUtteranceMs) {
            const bool ok = s.speech_ms >= kMinSpeechMs;
            std::string audio = std::move(s.utterance);
            s.in_speech = false;
            s.utterance.clear();
            s.speech_ms = 0;
            s.silence_ms = 0;
            if (ok) {
                *out_utterance = std::move(audio);
                completed = true;
                // Drop any backlog captured while this utterance ran so the
                // upcoming turn + TTS playout is not re-segmented.
                s.frame_accum.clear();
                break;
            }
        }
    }

    // Explicit flush (stream stopping): close an in-progress utterance if it
    // already holds enough speech.
    if (!completed && is_final && s.in_speech && s.speech_ms >= kMinSpeechMs &&
        !s.utterance.empty()) {
        *out_utterance = std::move(s.utterance);
        completed = true;
    }
    if (is_final) {
        s.in_speech = false;
        s.utterance.clear();
        s.speech_ms = 0;
        s.silence_ms = 0;
        s.pre_roll.clear();
        s.frame_accum.clear();
    }
    return completed;
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

extern "C" rac_result_t rac_voice_agent_feed_audio_proto(rac_voice_agent_handle_t handle,
                                                         const void* audio_data, size_t audio_size,
                                                         int32_t sample_rate_hz, int32_t channels,
                                                         int32_t encoding, rac_bool_t is_final,
                                                         rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)audio_data;
    (void)audio_size;
    (void)sample_rate_hz;
    (void)channels;
    (void)encoding;
    (void)is_final;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    using namespace rac::voice_agent::detail;
    if (!handle) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    // The in-core segmenter operates on 16 kHz mono PCM16 — the format every
    // SDK's AudioCaptureManager already produces. Treat UNSPECIFIED as PCM16.
    (void)sample_rate_hz;
    (void)channels;
    if (encoding != 0 &&
        encoding != static_cast<int32_t>(runanywhere::v1::AUDIO_ENCODING_PCM_S16_LE)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "feed_audio expects PCM_S16_LE mono @ 16 kHz");
    }

    // Admit under the in-flight barrier so destroy()'s drain covers any turn
    // this feed call triggers.
    InFlightGuard guard(handle);
    if (!guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "voice agent is shutting down");
    }
    if (!handle->is_configured.load(std::memory_order_acquire)) {
        emit_component_failure(handle, "voice_agent", RAC_ERROR_NOT_INITIALIZED,
                               "voice agent is not initialized");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "voice agent is not initialized");
    }

    // Segment under the feed lock only; the multi-second turn pipeline runs
    // outside it so a slow turn never blocks buffering of the next frame.
    std::string utterance;
    bool have_utterance = false;
    {
        std::lock_guard<std::mutex> seg_lock(handle->feed.mutex);
        have_utterance =
            feed_segment(handle->feed, audio_data, audio_size, is_final == RAC_TRUE, &utterance);
    }

    if (!have_utterance) {
        // No utterance closed this call: return an empty (default) result so
        // the SDK sees a valid buffer with no audio to play.
        runanywhere::v1::VoiceAgentResult empty;
        return copy_proto_message(empty, out_result);
    }

    const std::string turn_id = event_id("turn");
    runanywhere::v1::VoiceAgentResult result;
    const rac_result_t rc = d7_process_utterance(
        handle, utterance, /*session_id=*/std::string(), turn_id, /*request_id=*/std::string(),
        /*language_code=*/std::string(), /*event_callback=*/nullptr, /*user_data=*/nullptr,
        &result);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "voice turn failed");
    }
    return copy_proto_message(result, out_result);
#endif
}
