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

#include "rac/core/rac_audio_utils.h"
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
// How fast the ambient estimate may follow the room DOWNWARDS.
//
// This was an instant assignment — `noise_floor = level` for any frame quieter
// than the estimate — which does not track the ambience, it tracks the
// ambience's MINIMUM. Room noise is not a constant: a mic sitting in a measured
// -46.2 dBFS-mean room delivered frames ranging down past -55 dBFS, so the
// estimate collapsed onto the quietest frame ever seen and the relative gate
// (x2.2 = 6.8 dB above it) landed BELOW the room's own mean. Half of ordinary
// ambience then read as speech, which is not a subtle mistuning: the gate opened
// on nothing, and because the floor is deliberately frozen while an utterance is
// open, it could never re-learn its way out. The utterance ran to
// kMaxUtteranceMs, closed as a "finished turn", and Whisper answered fifteen
// seconds of room tone with the single word "The" — spoken back to the user by a
// full LLM+TTS turn, three times over, from a microphone that had heard nobody.
//
// A bounded fall keeps the property the instant drop was there for (a room that
// really does go quiet is followed within about a second) while making the
// estimate settle on what the room actually delivers rather than on its floor,
// so the x2.2 margin sits above the ambience instead of inside it.
constexpr float kNoiseFloorFall = 0.20f;
// Frames the ambient estimate must observe before the gate may open at all.
//
// `noise_floor` starts at zero — "nothing observed yet" — which makes the
// effective gate the absolute floor-of-the-floor (-72 dBFS) until a real
// measurement arrives. Every room on earth is louder than that, so the very
// first frame of every session opened the gate on ambience, and since the floor
// does not adapt while an utterance is open the session's first "turn" was
// guaranteed to be fifteen seconds of room tone. Listening before judging costs
// nothing — nobody has begun a sentence in the first moments of the capture
// graph coming up — and it is what gives the relative gate something true to be
// relative to.
//
// 800 ms, not less, because a real capture graph does not deliver its steady
// state immediately: measured on this Mac's built-in microphone the first frame
// came back at -69.9 dBFS (the device had not started yet) and the next seven
// climbed -46, -40, -38, -37, -37, -35, -33 as the input settled. An estimate
// taken over a shorter window, or taken as the minimum of the window, learns
// that ramp instead of the room.
constexpr int kFloorWarmupFrames = 8;
// How far above the ambient floor a frame must sit to COUNT towards
// kMinSpeechMs, as opposed to merely opening the gate.
//
// The gate stays deliberately sensitive (x2.2) so a sentence's first syllable is
// never clipped, but "loud enough to open" is far too weak a test for "a person
// was talking", which is what kMinSpeechMs is really asking. Room transients — a
// chair, a fan cycling, a door — clear 6.8 dB over their own floor all day.
//
// 11 dB is not a guess; it is where the measurement puts the knee. Replaying
// real captures of this machine's built-in microphone through this exact
// segmenter, counting utterances that would have been handed to STT:
//
//   margin      quiet room, 100 s      a voice at the mic, 23 s
//   ------      -----------------      ------------------------
//   none                        4                             8
//   8 dB                        3                             7
//   11 dB                       1                             6
//   14 dB                       1                             3
//
// So 11 dB removes three quarters of what the room produces while a voice is
// still heard six times out of eight — and pushing further starts costing real
// utterances without buying any more silence. The remaining one is why the VAD
// veto in d7_process_utterance exists: energy narrows the problem, it does not
// close it.
//
// Note for anyone re-measuring this on a Mac: do NOT use `say` through the
// built-in speakers as the "voice" input while the agent is running. The system
// echo-cancels its own output out of the capture stream, so that path arrives
// ~25 dB down (measured -39 dBFS against a -48 dBFS floor) and lands under this
// bar — correctly, because it is the agent's own loudspeaker, not a person. The
// figures above use a capture taken with the agent stopped, where nothing is
// being cancelled, which is what a human in the room actually looks like.
constexpr float kSpeechConfirmMultiplier = 3.5f;
constexpr int kEndOfUtteranceSilenceMs = 800;
constexpr int kMinSpeechMs = 300;
constexpr int kMaxUtteranceMs = 15000;
constexpr size_t kPreRollFrames = 3;

// --- Talking over an audible reply -----------------------------------------
//
// While the agent's own reply is coming out of the loudspeaker the microphone
// hears it too, at a level nobody can predict (speaker volume, room coupling,
// how the device is held). There is no acoustic echo canceller on this path, so
// something has to separate "the user interrupted" from "the agent heard
// itself".
//
// The thing that does it is that the core KNOWS WHAT THE AGENT IS SAYING: it
// synthesized the reply and handed the bytes to the SDK a moment ago. So it can
// predict the shape of its own echo — loud where the reply is loud, silent in
// the pauses between its sentences — and ask only whether the microphone is
// carrying more than that prediction accounts for. `echo_gain` is the one thing
// that has to be measured (how much of the loudspeaker this room and this
// microphone return), and it is a single scalar.
//
// The previous test compared the microphone against a running MAXIMUM of every
// level heard since the reply started. That estimate could only rise, which made
// it wrong in both directions at once, and measurably so. Over the real
// speaker -> room -> microphone path at 15% volume it fired on 0 of 6 recorded
// interruptions, including ones where the interrupting voice was 24 dB louder
// than the agent, because a frame that FAILED the test was folded into the
// maximum — so the interrupting voice raised, by up to this very margin, the bar
// it then had to clear. The louder the user spoke, the higher the bar went.
// It was also at its most deaf exactly where a person actually interrupts: in
// the pause between two of the agent's sentences, where the real echo is nothing
// but the latched maximum was still the loudest syllable of the whole reply.
//
// Failing this test means failing to notice an interruption, which is the safe
// direction to be wrong: the reply finishes and the user takes the turn the
// ordinary way. Passing it wrongly would make the agent cut itself off mid
// sentence, every turn — so the margin, the hold, and the settling window below
// are all kept.
constexpr float kBargeInEchoMargin = 2.5f;
constexpr int kBargeInMinFrames = 3;
// Frames of the reply that must actually have been HEARD before an interruption
// can be declared, i.e. frames used to measure `echo_gain`. Counted in frames
// carrying real signal rather than in elapsed time, because the platform player
// starts a device-dependent beat after the core hands the bytes over: counting
// elapsed frames would spend this window on room tone and then meet the reply's
// own onset already armed, which reads as the agent interrupting itself.
constexpr int kEchoSettleFrames = 4;
// How far the prediction may be misaligned with what the microphone hears
// before it stops being useful, expressed in analysis frames either side.
//
// The reply's envelope is indexed by frames elapsed since the audible window
// opened, so it drifts from reality by the player's start latency plus whatever
// jitter the feed introduces. Taking the loudest envelope frame within +/-200 ms
// makes the prediction tolerant of that in the direction that matters: a
// syllable about to arrive, or one just gone, still counts as "the agent is
// loud here", so the agent is never mistaken for a user.
constexpr int kEchoAlignFrames = 2;
// How long to wait for the reply to show up in the microphone at all before
// concluding it never will. One second: long enough for any platform player's
// start latency, short enough that a headphone user does not spend the whole
// reply unable to interrupt.
constexpr int kEchoUncoupledFrames = 10;
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

// Normalized RMS of one PCM16 frame (canonical RAC_AUDIO_PCM16_SCALE decode,
// then rac_audio_compute_rms — same units the threshold constants expect).
float frame_rms(const uint8_t* data, size_t bytes) {
    const size_t samples = bytes / kBytesPerSample;
    if (samples == 0)
        return 0.0f;
    const int16_t* pcm = reinterpret_cast<const int16_t*>(data);
    std::vector<float> normalized(samples);
    if (rac_audio_pcm16_to_float32(pcm, samples, normalized.data()) != RAC_SUCCESS)
        return 0.0f;
    float rms = 0.0f;
    if (rac_audio_compute_rms(normalized.data(), samples, &rms) != RAC_SUCCESS)
        return 0.0f;
    return rms;
}

// How loud the reply itself is at the moment it is being heard, in the same
// normalized-RMS units as `frame_rms`.
//
// @p elapsed_frames counts analysis frames since the audible window opened.
// Returns 0 outside the reply, which is what makes a pause between the agent's
// sentences collapse the barge-in threshold back onto the ordinary ambient gate
// — the moment a person is most likely to interrupt is then also the moment the
// agent is easiest to interrupt.
float expected_echo_level(const std::vector<float>& envelope, int64_t elapsed_frames) {
    if (envelope.empty() || elapsed_frames < 0)
        return 0.0f;
    const int64_t count = static_cast<int64_t>(envelope.size());
    const int64_t lo = std::max<int64_t>(0, elapsed_frames - kEchoAlignFrames);
    const int64_t hi = std::min<int64_t>(count, elapsed_frames + kEchoAlignFrames + 1);
    float peak = 0.0f;
    for (int64_t i = lo; i < hi; ++i)
        peak = std::max(peak, envelope[i]);
    return peak;
}

// Forget everything learned about the agent's own echo.
//
// Every one of these belongs to ONE audible reply, so they have to be dropped
// together wherever that reply's window ends — it closed on its own, the user
// took the turn, or the stream was flushed. They were being reset field by field
// at each of those sites, which is how `reply_envelope` would quietly be left
// behind at one of them and the next reply be judged against the last one's
// shape.
void reset_echo_estimate(rac_voice_agent_feed_state& s) {
    s.echo_frames = 0;
    s.echo_learn_frames = 0;
    s.echo_floor = 0.0f;
    s.echo_gain = 0.0f;
    s.barge_in_frames = 0;
    s.reply_envelope.clear();
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
    /// The energy gate closed this call, whether or not the utterance behind it
    /// survived to become a turn.
    ///
    /// Reported separately from `utterance_closed` because the two are not the
    /// same event and conflating them left a false claim on screen: the gate
    /// opens on a cough, `speech_started` says so, the utterance is then
    /// discarded for holding too little speech — and with no counterpart event
    /// the panel went on saying "Listening…" (its wording for "I can hear you
    /// talking") for the rest of the session, over a room where nobody was.
    bool speech_ended{false};
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

        // Learn the room before judging it. The loudest warm-up frame is the
        // estimate — the same rule `echo_floor` uses for the same reason. Taking
        // the loudest can only over-estimate the room, which costs a fraction of
        // a second of deafness while the fall tracker walks it down to the truth;
        // taking the quietest under-estimates it, and an under-estimated floor
        // is exactly the failure this whole warm-up exists to prevent.
        if (s.warmup_frames < kFloorWarmupFrames) {
            ++s.warmup_frames;
            s.noise_floor = std::max(s.noise_floor, level);
            continue;
        }

        // The gate is relative to whatever this microphone actually delivers;
        // kSpeechRmsFloor only rules out dead air.
        const float ambient_gate =
            std::max(kSpeechRmsFloor, s.noise_floor * kSpeechFloorMultiplier);
        float threshold = ambient_gate;
        bool barge_in_armed = false;
        float expected_echo = 0.0f;
        if (reply_audible) {
            // Where the reply has got to, and therefore how loud the agent is
            // entitled to sound right now. `echo_frames` counts from the instant
            // the audible window opened, which is when the SDK was handed the
            // bytes; kEchoAlignFrames absorbs the player's start latency.
            expected_echo = expected_echo_level(s.reply_envelope, s.echo_frames);
            ++s.echo_frames;
            // Armed once the coupling has been measured — or once it is clear
            // there is nothing to measure. A reply routed to headphones, or to a
            // speaker this microphone simply cannot hear, produces no echo at
            // all; waiting forever for one would mean a user on headphones could
            // never interrupt by voice, which is measurably what happened.
            // Nothing audible to confuse a voice with is the easiest case, not
            // the hardest, so the ordinary ambient gate decides it.
            barge_in_armed =
                s.echo_learn_frames >= kEchoSettleFrames || s.echo_frames >= kEchoUncoupledFrames;
            // What the microphone should be reading right now: the predicted
            // echo and the room, which are independent and therefore add in
            // POWER rather than amplitude.
            const float predicted = s.echo_gain * expected_echo;
            s.echo_floor = std::sqrt(predicted * predicted + s.noise_floor * s.noise_floor);
            threshold = std::max(threshold, s.echo_floor * kBargeInEchoMargin);
        } else {
            reset_echo_estimate(s);
        }

        const bool is_speech = level >= threshold;
        // Opening the gate and having been a voice are two different claims, and
        // only the second one may end a turn. `threshold` answers the first;
        // this answers the second. Never below the gate, so a barge-in still has
        // to clear the echo estimate too.
        const bool is_confirmed_speech =
            level >= std::max(threshold, s.noise_floor * kSpeechConfirmMultiplier);

        // Measure how much of the loudspeaker this room returns to this
        // microphone, from the opening frames of the reply and then STOP.
        //
        // Stopping is the point. Speaker volume, room and device position do not
        // change during one reply, so there is nothing left to learn — whereas
        // going on "learning" from later frames is precisely how the interrupting
        // voice used to be absorbed into the estimate of the agent's own echo and
        // raise the bar against itself. The reply getting louder mid-sentence,
        // which is what the old running maximum was really for, is now carried by
        // `reply_envelope` instead, where it belongs.
        //
        // Only the part of the frame the loudspeaker can account for is measured:
        // the room and the echo add in power, so the room's contribution is
        // subtracted the same way. That also makes the estimate self-limiting —
        // a frame carrying nothing but room noise yields no coupling at all
        // rather than a huge ratio against a quiet moment of the reply.
        if (reply_audible && !barge_in_armed && expected_echo > 0.0f) {
            const float excess_power = level * level - s.noise_floor * s.noise_floor;
            if (excess_power > 0.0f) {
                ++s.echo_learn_frames;
                s.echo_gain = std::max(s.echo_gain, std::sqrt(excess_power) / expected_echo);
            }
        }

        // The whole barge-in decision, one line per frame, for the only window
        // where it is being made. Nothing above this layer can see any of these
        // numbers, and without them a missed interruption is indistinguishable
        // from a broken microphone — which is how a running maximum that could
        // never come down survived as long as it did. DEBUG level, so the level
        // check discards it before formatting on any build that is not looking.
        if (reply_audible) {
            RAC_LOG_DEBUG("VoiceAgent.Feed",
                          "barge-in frame=%d level=%.5f floor=%.5f predicted_echo=%.5f "
                          "gain=%.2f threshold=%.5f speech=%d run=%d armed=%d",
                          s.echo_frames, static_cast<double>(level),
                          static_cast<double>(s.noise_floor), static_cast<double>(s.echo_floor),
                          static_cast<double>(s.echo_gain), static_cast<double>(threshold),
                          is_speech ? 1 : 0, s.barge_in_frames, barge_in_armed ? 1 : 0);
        }

        // Only adapt the floor while idle (between utterances). Adapting
        // mid-utterance lets inter-word pauses inflate the floor and lock out
        // the next turn. Never adapt from the agent's own playout — that would
        // train the floor on the loudspeaker and deafen the next turn. Fall
        // quickly towards a quieter ambient, creep up slowly otherwise — but
        // never jump straight onto the quietest frame (see kNoiseFloorFall).
        if (!s.in_speech && !reply_audible) {
            if (level < s.noise_floor) {
                s.noise_floor += (level - s.noise_floor) * kNoiseFloorFall;
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
            // Say what the gate is measuring when nothing has cleared it for a
            // long time. See rac_voice_agent_feed_state::gate_shut_ms.
            if (open_gate) {
                s.gate_shut_ms = 0;
                s.gate_shut_peak = 0.0f;
                s.gate_shut_reported = false;
            } else if (!reply_audible) {
                s.gate_shut_ms += kFrameMs;
                s.gate_shut_peak = std::max(s.gate_shut_peak, level);
                if (!s.gate_shut_reported && s.gate_shut_ms >= kSilentInputWarnMs) {
                    s.gate_shut_reported = true;
                    RAC_LOG_INFO("VoiceAgent.Feed",
                                 "no speech gate for %lld ms: loudest frame %.5f, floor "
                                 "%.5f, gate %.5f",
                                 static_cast<long long>(s.gate_shut_ms),
                                 static_cast<double>(s.gate_shut_peak),
                                 static_cast<double>(s.noise_floor),
                                 static_cast<double>(threshold));
                }
            }
            if (open_gate) {
                s.in_speech = true;
                s.speech_ms = is_confirmed_speech ? kFrameMs : 0;
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
                reset_echo_estimate(s);
                s.silent_input_ms = 0;
                s.silent_input_peak = 0.0f;
                s.silent_input_reported = false;
            }
            continue;
        }

        s.utterance.append(reinterpret_cast<const char*>(frame.data()), frame.size());
        // Endpointing timing stays the gate's job — a pause between words is
        // "not speaking" at the gate's sensitivity, and widening that would
        // change how quickly turns end. Only what `speech_ms` counts changed.
        if (is_confirmed_speech) {
            s.speech_ms += kFrameMs;
        }
        s.silence_ms = is_speech ? 0 : s.silence_ms + kFrameMs;

        const int utterance_ms =
            static_cast<int>((s.utterance.size() / kBytesPerSample) * 1000 / kSampleRateHz);
        if (s.silence_ms >= kEndOfUtteranceSilenceMs || utterance_ms >= kMaxUtteranceMs) {
            const bool ok = s.speech_ms >= kMinSpeechMs;
            std::string audio = std::move(s.utterance);
            // What the segmenter measured, once per utterance. Every threshold
            // in this file is relative to `noise_floor`, so an utterance that
            // was wrongly kept or wrongly dropped is unexplainable without it —
            // and the alternative, reading it back off a parallel recording of
            // the same microphone, does not see the same signal the agent got.
            RAC_LOG_INFO("VoiceAgent.Feed",
                         "utterance closed: %d ms, speech %d ms, floor %.5f, kept=%d",
                         static_cast<int>((audio.size() / kBytesPerSample) * 1000 / kSampleRateHz),
                         s.speech_ms, static_cast<double>(s.noise_floor), ok ? 1 : 0);
            s.in_speech = false;
            s.utterance.clear();
            s.speech_ms = 0;
            s.silence_ms = 0;
            outcome.speech_ended = true;
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
        // A flush with the gate still open ends that speech too, so the pair
        // stays balanced across a stream that stops mid-sentence.
        if (s.in_speech) {
            outcome.speech_ended = true;
        }
        s.in_speech = false;
        s.utterance.clear();
        s.speech_ms = 0;
        s.silence_ms = 0;
        s.pre_roll.clear();
        s.frame_accum.clear();
        reset_echo_estimate(s);
        s.silent_input_ms = 0;
        s.silent_input_peak = 0.0f;
        s.silent_input_reported = false;
        // A flush ends this capture stream; the next one may well be a different
        // input device in a different room, so the ambient estimate is re-learned
        // rather than inherited.
        s.warmup_frames = 0;
        s.noise_floor = 0.0f;
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

// The reply's own loudness over time, one value per kFrameMs of playout.
//
// This is the core telling itself what it is about to sound like, so that a
// microphone frame arriving during playout can be compared against a prediction
// instead of against the loudest thing heard so far. It is the only reason the
// threshold can come back down during the pauses between the agent's sentences.
//
// Same canonical 44-byte header as wav_duration_ms, and the same policy on
// anything that does not match it: return nothing rather than a guess. An empty
// envelope leaves the barge-in detector unarmed for that reply, so the reply
// simply plays to the end — the safe direction.
//
// The reply is resampled to nothing and decoded from nothing: it is read at its
// own sample rate, and the per-frame RMS is normalized the same way frame_rms
// normalizes the microphone. Only the RATIO of the two is ever used, so the two
// signals never have to share a sample rate or an absolute scale.
void build_reply_envelope(const std::string& wav, std::vector<float>* out) {
    out->clear();
    constexpr size_t kHeaderBytes = 44;
    if (wav.size() < kHeaderBytes)
        return;
    const auto* bytes = reinterpret_cast<const uint8_t*>(wav.data());
    auto tag_is = [bytes](size_t offset, const char* tag) {
        return std::memcmp(bytes + offset, tag, 4) == 0;
    };
    if (!tag_is(0, "RIFF") || !tag_is(8, "WAVE") || !tag_is(12, "fmt ") || !tag_is(36, "data"))
        return;
    auto read_u16 = [bytes](size_t offset) {
        uint16_t value = 0;
        std::memcpy(&value, bytes + offset, sizeof(value));
        return value;
    };
    auto read_u32 = [bytes](size_t offset) {
        uint32_t value = 0;
        std::memcpy(&value, bytes + offset, sizeof(value));
        return value;
    };
    const uint16_t channels = read_u16(22);
    const uint32_t sample_rate = read_u32(24);
    const uint16_t bits = read_u16(34);
    const uint32_t data_bytes = read_u32(40);
    if (channels == 0 || sample_rate == 0 || bits != 16 || data_bytes == 0)
        return;

    const size_t available = std::min<size_t>(data_bytes, wav.size() - kHeaderBytes);
    const size_t total_frames = available / (static_cast<size_t>(channels) * sizeof(int16_t));
    const size_t frames_per_window =
        static_cast<size_t>(sample_rate) * static_cast<size_t>(kFrameMs) / 1000;
    if (total_frames == 0 || frames_per_window == 0)
        return;

    const auto* pcm = reinterpret_cast<const int16_t*>(bytes + kHeaderBytes);
    out->reserve(total_frames / frames_per_window + 1);
    std::vector<float> window;
    window.reserve(frames_per_window);
    for (size_t start = 0; start < total_frames; start += frames_per_window) {
        const size_t count = std::min(frames_per_window, total_frames - start);
        window.resize(count);
        for (size_t i = 0; i < count; ++i) {
            // Channel 0 only. A reply is mono in practice, and where it is not,
            // one channel still carries the envelope this is measuring.
            window[i] = static_cast<float>(pcm[(start + i) * channels]) / RAC_AUDIO_PCM16_SCALE;
        }
        float rms = 0.0f;
        if (rac_audio_compute_rms(window.data(), count, &rms) != RAC_SUCCESS)
            rms = 0.0f;
        out->push_back(rms);
    }
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

    // Paired with USER_SPEECH_STARTED above on every path, including the one
    // where the utterance is thrown away — an unmatched "started" is a frontend
    // stuck rendering speech that stopped.
    if (observed.speech_ended) {
        emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED);
    }

    if (!observed.utterance_closed) {
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
    // The recognizer heard no speech in what the segmenter handed it, so there
    // is no turn — the same answer as a feed call that closed no utterance at
    // all, and it belongs on the same path. Reporting it as a feed error made
    // the SDK log `Voice feed failed: rc=-231` for a microphone that was working
    // perfectly, which is a lie that costs somebody an afternoon.
    if (rc == RAC_ERROR_INSUFFICIENT_AUDIO_DATA) {
        runanywhere::v1::VoiceAgentResult empty;
        return copy_proto_message(empty, out_result);
    }
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
            reset_echo_estimate(handle->feed);
            // What the agent is about to sound like, frame by frame. This is the
            // reference the next few seconds of microphone input are judged
            // against; without it the detector stays unarmed and the reply plays
            // to the end.
            build_reply_envelope(result.synthesized_audio(), &handle->feed.reply_envelope);
        }
    }
    return copy_proto_message(result, out_result);
#endif
}
