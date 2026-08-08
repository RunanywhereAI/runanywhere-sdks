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
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
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
// Floor-of-the-floor, NOT the gate. -72 dBFS: below this a frame carries no
// more energy than a muted or disconnected input, so opening on it would only
// hand STT noise. Everything above it is decided RELATIVE to the ambient floor
// this mic actually delivers (kSpeechFloorMultiplier below), which is the whole
// point: the previous absolute 0.015 (-36.5 dBFS) gate meant a measured
// 0.000414-RMS (-67.7 dBFS) mic feed never opened it, so streaming STT produced
// no partials and no final and the agent sat in "Listening" indefinitely — while
// batch STT transcribed the very same audio verbatim and Silero VAD fired on it.
// Any low-gain mic or quiet talker reproduces that, and the failure is
// indistinguishable from a broken pipeline.
//
// The number was 0.0005 (-66 dBFS), which is ABOVE the 0.000414 feed the comment
// cites as the motivating failure — so that exact feed still could not open the
// gate and the agent still sat in "Listening" with no explanation. -72 dBFS
// clears it with margin and is still ~18 dB above dithered dead air, and nothing
// downstream loses protection: a mic whose own noise sits at this level has that
// noise learned as its ambient floor within a second, so the RELATIVE gate
// (x2.2) is what keeps it shut. Kept in step with kFallbackNoiseFloorRms in
// features/stt/rac_stt_stream.cpp, which is the same physical quantity for the
// one-shot STT segmenter.
constexpr float kSpeechRmsFloor = 0.00025f;
constexpr float kSpeechFloorMultiplier = 2.2f;
constexpr float kNoiseFloorRise = 0.05f;
constexpr int kEndOfUtteranceSilenceMs = 800;
constexpr int kMinSpeechMs = 300;
constexpr int kMaxUtteranceMs = 15000;
constexpr size_t kPreRollFrames = 3;

// --- Talking over an audible reply -----------------------------------------
//
// While the agent's own reply is coming out of the loudspeaker the microphone
// hears it too, at a level nobody can predict (speaker volume, room coupling,
// how the device is held). There is no acoustic echo canceller on this path, so
// the ONLY thing separating "the user interrupted" from "the agent heard itself"
// is that a real interrupting voice arrives ON TOP of the echo and is therefore
// louder than it. `echo_floor` tracks what the agent sounds like to its own mic
// during that window; a barge-in has to clear it by this margin and hold for
// kBargeInMinFrames so a single loud syllable of the reply cannot trip it.
//
// Failing this test means failing to notice an interruption, which is the safe
// direction to be wrong: the reply finishes and the user takes the turn the
// ordinary way. Passing it wrongly would make the agent cut itself off mid
// sentence, every turn.
constexpr float kBargeInEchoMargin = 2.5f;
constexpr int kBargeInMinFrames = 3;
constexpr int kEchoSettleFrames = 4;
// Playout does not stop on the exact millisecond the WAV's own duration says it
// will — the platform player starts a beat after the core hands the bytes over
// and drains a beat after the last sample. Frames landing in that overhang are
// still the agent, so they stay inside the echo-judged window rather than
// becoming the opening of a turn made of the agent's own last syllable.
constexpr int64_t kReplyTailGuardMs = 250;

// How long the input may deliver nothing at all before the core says so.
//
// Frames arriving with less energy than kSpeechRmsFloor are not "silence" —
// ordinary room silence, and even a mic's own self-noise, sits well above that
// floor. They mean the capture graph is handing over dead air: a muted mic, the
// wrong input device, a host with no audio device. Nothing else in the stack can
// tell the user that, so the panel would otherwise keep asserting it is
// listening forever. Eight seconds is long enough that no real pause between
// turns reaches it.
constexpr int64_t kSilentInputWarnMs = 8000;

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

// What one feed call observed. Grouped rather than passed as four out-params
// because every field is a distinct thing the SDK has to act on, at a different
// moment, and a bool-soup signature had already started to hide that.
struct feed_outcome {
    /// An utterance closed this call and was moved into `out_utterance`.
    bool utterance_closed{false};
    /// The energy gate opened this call — the moment the core first hears a
    /// voice. Reported separately from the completed turn because a turn only
    /// arrives seconds later, far too late for an SDK to cut a reply the user
    /// talked over.
    bool speech_started{false};
    /// That onset happened while the agent's own reply was still audible AND
    /// cleared the echo estimate, i.e. the user really is talking over it.
    bool barge_in{false};
    /// The input has delivered nothing but dead air for kSilentInputWarnMs and
    /// has not said so yet.
    bool input_silent{false};
    /// Loudest frame during that dead stretch, so the diagnostic reports a
    /// measurement instead of an adjective.
    float silent_peak{0.0f};
};

// Accumulate fed audio into fixed analysis frames and run energy endpointing.
// At most one utterance is reported per call; any buffered backlog is dropped so
// the device's own TTS playout is not folded into the next turn (mirrors the
// SDK's former discard-pending-chunks behavior). The adaptive noise floor
// persists across turns; only transient state resets.
//
// @p now_ms is the caller's wall clock, used to decide whether the reply handed
// back by the previous call is still coming out of the loudspeaker.
feed_outcome feed_segment(rac_voice_agent_feed_state& s, const void* data, size_t size,
                          bool is_final, int64_t now_ms, std::string* out_utterance) {
    if (data && size > 0) {
        const uint8_t* bytes = static_cast<const uint8_t*>(data);
        s.frame_accum.insert(s.frame_accum.end(), bytes, bytes + size);
    }

    feed_outcome outcome;
    while (s.frame_accum.size() >= kFrameBytes) {
        std::vector<uint8_t> frame(s.frame_accum.begin(), s.frame_accum.begin() + kFrameBytes);
        s.frame_accum.erase(s.frame_accum.begin(), s.frame_accum.begin() + kFrameBytes);

        const float level = frame_rms(frame.data(), frame.size());
        const bool reply_audible = s.reply_audible_until_ms > now_ms;

        // Dead-input watch. Suspended while the agent is audible: the
        // loudspeaker guarantees signal, so a quiet frame there says nothing
        // about the microphone.
        if (!reply_audible) {
            if (level >= kSpeechRmsFloor) {
                // Signal returned, so the stretch restarts — but the report is
                // NOT re-armed here. Re-arming on any above-floor frame made a
                // virtual/loopback input that returns to exact zeros between
                // turns say this seven times in six minutes (measured), which
                // trains the user to ignore the one message that matters. The
                // claim is only worth repeating once the agent has actually
                // heard a voice, which is where it is re-armed (gate open).
                s.silent_input_ms = 0;
                s.silent_input_peak = 0.0f;
            } else {
                s.silent_input_ms += kFrameMs;
                s.silent_input_peak = std::max(s.silent_input_peak, level);
                if (!s.silent_input_reported && s.silent_input_ms >= kSilentInputWarnMs) {
                    s.silent_input_reported = true;
                    outcome.input_silent = true;
                    outcome.silent_peak = s.silent_input_peak;
                }
            }
        }

        // The gate is relative to whatever this microphone actually delivers;
        // kSpeechRmsFloor only rules out dead air.
        float threshold = std::max(kSpeechRmsFloor, s.noise_floor * kSpeechFloorMultiplier);
        bool barge_in_armed = false;
        if (reply_audible) {
            ++s.echo_frames;
            if (s.echo_frames <= kEchoSettleFrames) {
                // Learning window: whatever arrives now is the agent hearing
                // itself (the user cannot have reacted to a reply that has
                // barely started), so take the loudest of it as the bar.
                s.echo_floor = std::max(s.echo_floor, level);
            } else {
                barge_in_armed = true;
            }
            threshold = std::max(threshold, s.echo_floor * kBargeInEchoMargin);
        } else {
            s.echo_frames = 0;
            s.echo_floor = 0.0f;
            s.barge_in_frames = 0;
        }

        const bool is_speech = level >= threshold;

        // Keep raising the bar from echo-only frames after the learning window
        // so a reply that gets louder mid-sentence still cannot trip it.
        if (reply_audible && !is_speech) {
            s.echo_floor = std::max(s.echo_floor, level);
        }

        // Only adapt the floor while idle (between utterances). Adapting
        // mid-utterance lets inter-word pauses inflate the floor and lock out
        // the next turn. Never adapt from the agent's own playout — that would
        // train the floor on the loudspeaker and deafen the next turn. Drop
        // instantly to any quieter ambient; creep up slowly otherwise.
        if (!s.in_speech && !reply_audible) {
            if (level < s.noise_floor) {
                s.noise_floor = level;
            } else if (!is_speech) {
                s.noise_floor += (level - s.noise_floor) * kNoiseFloorRise;
            }
        }

        if (!s.in_speech) {
            // A voice arriving over an audible reply has to hold for a few
            // frames: one loud syllable of the agent's own sentence must not be
            // able to cut it off.
            if (reply_audible) {
                s.barge_in_frames = is_speech ? s.barge_in_frames + 1 : 0;
            }
            const bool open_gate =
                is_speech &&
                (!reply_audible || (barge_in_armed && s.barge_in_frames >= kBargeInMinFrames));

            s.pre_roll.push_back(std::move(frame));
            if (s.pre_roll.size() > kPreRollFrames)
                s.pre_roll.pop_front();
            if (open_gate) {
                s.in_speech = true;
                s.speech_ms = kFrameMs;
                s.silence_ms = 0;
                s.utterance.clear();
                for (const auto& buffered : s.pre_roll)
                    s.utterance.append(reinterpret_cast<const char*>(buffered.data()),
                                       buffered.size());
                s.pre_roll.clear();
                outcome.speech_started = true;
                // Reported once per reply: close the window here so the rest of
                // the same utterance does not repeat it.
                outcome.barge_in = reply_audible;
                s.reply_audible_until_ms = 0;
                s.barge_in_frames = 0;
                s.echo_frames = 0;
                s.echo_floor = 0.0f;
                s.silent_input_ms = 0;
                s.silent_input_peak = 0.0f;
                s.silent_input_reported = false;
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
                outcome.utterance_closed = true;
                // Drop any backlog captured while this utterance ran so the
                // upcoming turn + TTS playout is not re-segmented.
                s.frame_accum.clear();
                break;
            }
        }
    }

    // Explicit flush (stream stopping): close an in-progress utterance if it
    // already holds enough speech.
    if (!outcome.utterance_closed && is_final && s.in_speech && s.speech_ms >= kMinSpeechMs &&
        !s.utterance.empty()) {
        *out_utterance = std::move(s.utterance);
        outcome.utterance_closed = true;
    }
    if (is_final) {
        s.in_speech = false;
        s.utterance.clear();
        s.speech_ms = 0;
        s.silence_ms = 0;
        s.pre_roll.clear();
        s.frame_accum.clear();
        s.barge_in_frames = 0;
        s.echo_frames = 0;
        s.echo_floor = 0.0f;
        s.silent_input_ms = 0;
        s.silent_input_peak = 0.0f;
        s.silent_input_reported = false;
    }
    return outcome;
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

// Tell the SDK the microphone is handing over dead air.
//
// Without this the panel keeps asserting it is listening for as long as the user
// is willing to wait, and a muted mic, a wrong input device or a host with no
// audio device all look exactly like a broken STT pipeline. Nothing above the
// core can tell the difference — only this layer sees the frame levels — so this
// is the one place the truth exists.
//
// Reported as a RECOVERABLE session error: the session is still running and will
// start hearing the moment real signal arrives, so it must not tear anything
// down. Every SDK already folds a recoverable session error onto its
// "show this message, keep the session" path.
void emit_input_too_quiet(rac_voice_agent_handle_t handle, float peak_level, int64_t silent_ms) {
    // 20*log10 of the peak frame RMS. -inf for a true digital zero, which is
    // itself worth printing plainly rather than as a number.
    char message[224];
    if (peak_level > 0.0f) {
        std::snprintf(message, sizeof(message),
                      "I can't hear you — the microphone is delivering almost no signal (peak "
                      "%.1f dBFS over the last %llds). Check that the right input device is "
                      "selected and not muted.",
                      20.0 * std::log10(static_cast<double>(peak_level)),
                      static_cast<long long>(silent_ms / 1000));
    } else {
        std::snprintf(message, sizeof(message),
                      "I can't hear you — the microphone is delivering digital silence (every "
                      "sample zero for %llds). Check that the right input device is selected "
                      "and not muted.",
                      static_cast<long long>(silent_ms / 1000));
    }

    runanywhere::v1::VoiceEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_ERROR);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_WARNING);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AUDIO);
    auto* session_error = event.mutable_session_error();
    session_error->set_code(runanywhere::v1::ERROR_CODE_INSUFFICIENT_AUDIO_DATA);
    session_error->set_message(message);
    session_error->set_failed_component("audio");
    session_error->set_recoverable(true);
    rac::voice_agent::detail::emit_generated_voice_event(handle, event,
                                                         runanywhere::v1::ERROR_SEVERITY_WARNING);
    RAC_LOG_WARNING("VoiceAgent.Feed", "%s", message);
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
    feed_outcome observed;
    int64_t silent_ms = 0;
    {
        std::lock_guard<std::mutex> seg_lock(handle->feed.mutex);
        observed = feed_segment(handle->feed, audio_data, audio_size, is_final == RAC_TRUE,
                                rac_get_current_time_ms(), &utterance);
        silent_ms = handle->feed.silent_input_ms;
    }

    if (observed.input_silent) {
        emit_input_too_quiet(handle, observed.silent_peak, silent_ms);
    }

    if (observed.speech_started) {
        if (observed.barge_in) {
            emit_user_barge_in(handle);
        }
        emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED);
    }

    if (!observed.utterance_closed) {
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
            handle->feed.reply_audible_until_ms =
                rac_get_current_time_ms() + audible_ms + kReplyTailGuardMs;
            // Everything buffered while the turn was being computed predates
            // playout, so it is neither part of the finished turn nor of the
            // agent's voice. Feeding it now would seed the echo estimate from
            // pre-playout quiet and then let the reply's own onset clear the bar
            // it set — the agent cutting itself off on every reply. It is
            // dropped here, in the core, so no SDK has to know to do it.
            handle->feed.frame_accum.clear();
            handle->feed.echo_frames = 0;
            handle->feed.echo_floor = 0.0f;
            handle->feed.barge_in_frames = 0;
        }
    }
    return copy_proto_message(result, out_result);
#endif
}
