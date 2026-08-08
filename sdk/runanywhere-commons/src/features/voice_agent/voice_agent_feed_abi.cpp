/**
 * @file voice_agent_feed_abi.cpp
 * @brief Streaming audio-ingress voice-agent C ABI —
 *        `rac_voice_agent_feed_audio_proto`.
 *
 * The C core owns no microphone (see the "Audio-Ingress Contract" in
 * rac_voice_agent.h). Platform SDKs capture raw mic frames and push them
 * here continuously; this TU performs energy-based utterance segmentation
 * in-core (the logic that previously lived duplicated in every SDK's
 * VoiceAgentMicDriver) and, once an utterance closes, runs the shared
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
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
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
//
// @p out_speech_started is set when the energy gate opened during this call.
// That is the moment the core first hears a voice, and it is the whole reason
// hands-free barge-in was impossible: this function used to answer a frame only
// with a *completed turn*, seconds later, so an SDK feeding through playout
// could not learn in time to cut the sentence the user talked over. Reporting
// the onset separately is what lets it.
bool feed_segment(rac_voice_agent_feed_state& s, const void* data, size_t size, bool is_final,
                  std::string* out_utterance, bool* out_speech_started) {
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
                if (out_speech_started)
                    *out_speech_started = true;
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

        const int utterance_ms =
            static_cast<int>((s.utterance.size() / kBytesPerSample) * 1000 / kSampleRateHz);
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

// How long the reply we just handed the SDK will be audible for, in ms.
//
// This is what bounds the barge-in window, and the bound is what keeps the
// signal honest for BOTH driver shapes. A half-duplex driver stops feeding for
// the duration of playout, so its next onset necessarily lands after this
// window and is an ordinary new turn. A driver that keeps feeding produces an
// onset inside the window, and that one really is the user talking over the
// agent. Without the bound every first utterance after any reply would be
// reported as a barge-in.
//
// The bytes are a canonical WAV this file's own pipeline produced
// (rac_audio_float32_to_wav), so the fixed header layout is safe to read.
// Returns 0 for anything that does not match it — an unarmed window reports no
// barge-in, which is the right way to be wrong.
int64_t wav_duration_ms(const std::string& wav) {
    constexpr size_t kHeaderBytes = 44;
    if (wav.size() < kHeaderBytes)
        return 0;
    const auto* bytes = reinterpret_cast<const uint8_t*>(wav.data());
    auto tag_is = [bytes](size_t offset, const char* tag) {
        return std::memcmp(bytes + offset, tag, 4) == 0;
    };
    if (!tag_is(0, "RIFF") || !tag_is(8, "WAVE") || !tag_is(12, "fmt ") || !tag_is(36, "data"))
        return 0;
    auto read_u32 = [bytes](size_t offset) {
        uint32_t value = 0;
        std::memcpy(&value, bytes + offset, sizeof(value));
        return value;
    };
    const uint32_t byte_rate = read_u32(28);
    const uint32_t data_bytes = read_u32(40);
    if (byte_rate == 0 || data_bytes == 0)
        return 0;
    return static_cast<int64_t>(data_bytes) * 1000 / static_cast<int64_t>(byte_rate);
}

// Tell the SDK the user has started talking over an audible reply. Only the SDK
// can stop the speaker, and only the core knows a voice arrived, so this event
// is the whole handshake. It fires on speech ONSET rather than on the closed
// utterance: waiting for the endpoint (and then a full replacement turn) would
// arrive seconds after the sentence the user interrupted had finished playing.
void emit_user_barge_in(rac_voice_agent_handle_t handle) {
    runanywhere::v1::VoiceEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* interrupted = event.mutable_interrupted();
    interrupted->set_reason(runanywhere::v1::INTERRUPT_REASON_USER_BARGE_IN);
    interrupted->set_detail("user started speaking while the reply was playing");
    rac::voice_agent::detail::emit_generated_voice_event(handle, event);
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

extern "C" rac_result_t rac_voice_agent_feed_audio_proto(rac_voice_agent_handle_t handle,
                                                         const uint8_t* frame_proto_bytes,
                                                         size_t frame_proto_size,
                                                         rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)frame_proto_bytes;
    (void)frame_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    using namespace rac::voice_agent::detail;
    if (!handle) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    runanywhere::v1::VoiceAgentAudioFrame frame;
    if (!frame_proto_bytes || frame_proto_size == 0 ||
        !frame.ParseFromArray(frame_proto_bytes, static_cast<int>(frame_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VoiceAgentAudioFrame");
    }
    const void* audio_data = frame.audio_data().data();
    const size_t audio_size = frame.audio_data().size();
    const rac_bool_t is_final = frame.is_final() ? RAC_TRUE : RAC_FALSE;
    // The in-core segmenter operates on 16 kHz mono PCM16 — the format every
    // SDK's AudioCaptureManager already produces. Treat UNSPECIFIED as PCM16.
    if (frame.encoding() != runanywhere::v1::AUDIO_ENCODING_UNSPECIFIED &&
        frame.encoding() != runanywhere::v1::AUDIO_ENCODING_PCM_S16_LE) {
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
    // Events are emitted after the lock is released: they run caller callbacks.
    std::string utterance;
    bool have_utterance = false;
    bool speech_started = false;
    bool barge_in = false;
    {
        std::lock_guard<std::mutex> seg_lock(handle->feed.mutex);
        have_utterance = feed_segment(handle->feed, audio_data, audio_size, is_final == RAC_TRUE,
                                      &utterance, &speech_started);
        if (speech_started) {
            // An onset while the reply is still audible is a barge-in. Reported
            // once per reply: the window is closed here so the rest of the same
            // utterance does not repeat it.
            barge_in = handle->feed.reply_audible_until_ms > rac_get_current_time_ms();
            handle->feed.reply_audible_until_ms = 0;
        }
    }

    if (speech_started) {
        if (barge_in) {
            emit_user_barge_in(handle);
        }
        emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED);
    }

    if (!have_utterance) {
        // No utterance closed this call: return an empty (default) result so
        // the SDK sees a valid buffer with no audio to play.
        runanywhere::v1::VoiceAgentResult empty;
        return copy_proto_message(empty, out_result);
    }
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED);

    const std::string turn_id = event_id("turn");
    runanywhere::v1::VoiceAgentResult result;
    const rac_result_t rc = d7_process_utterance(
        handle, utterance, /*session_id=*/std::string(), turn_id, /*request_id=*/std::string(),
        /*language_code=*/std::string(), /*event_callback=*/nullptr, /*user_data=*/nullptr,
        &result);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "voice turn failed");
    }
    // The SDK is about to make this audible. For as long as it is, the agent is
    // the one talking — which is what turns an onset in that window into a
    // barge-in rather than an ordinary new turn.
    if (result.has_synthesized_audio()) {
        const int64_t audible_ms = wav_duration_ms(result.synthesized_audio());
        if (audible_ms > 0) {
            std::lock_guard<std::mutex> seg_lock(handle->feed.mutex);
            handle->feed.reply_audible_until_ms = rac_get_current_time_ms() + audible_ms;
        }
    }
    return copy_proto_message(result, out_result);
#endif
}
