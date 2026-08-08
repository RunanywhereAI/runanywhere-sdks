/**
 * @file voice_agent_internal.h
 * @brief Internal layout of `rac_voice_agent` shared across the
 *        `voice_agent*.cpp` translation units.
 *
 * NOT part of the public C ABI; do NOT include from anything under
 * `include/rac/`. Only the implementation files inside
 * `src/features/voice_agent/` may include this header.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
#define RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

#include "rac/core/rac_types.h"
#include "rac/rac_defaults_generated.h"

/// Voice-assistant LLM turn defaults (commons). The voice pipeline feeds these
/// to every LLM turn so replies are short, spoken, and context-aware instead of
/// the model's raw default (which rambles / emits markdown for a raw transcript).
/// Internal — no proto/ABI surface.
inline constexpr const char* kVoiceAgentSystemPrompt =
    "You are a helpful voice assistant. Respond in one or two short, natural, "
    "spoken sentences. Be direct, warm, and conversational. Do not use markdown, "
    "bullet points, code blocks, or emoji. If you are unsure or lack the "
    "information, say so briefly instead of guessing.";
/// Spoken replies should be short. Ninety-six tokens is enough for the one or
/// two sentences requested above without leaving a long hidden-reasoning
/// runway on thinking-capable models.
///
/// Declared in idl/sdk_defaults.proto (VoiceAgentDefaults) so the Web SDK,
/// which assembles its own LLM options in TypeScript rather than going through
/// this path, reads the same number instead of its own.
inline constexpr int32_t kVoiceAgentMaxTokens = RAC_DEFAULT_VOICE_AGENT_MAX_TOKENS;
/// Greedy decoding keeps a spoken turn stable and avoids sampling a verbose
/// continuation. A positive seed is also supplied for backends that still
/// construct a sampler when temperature is zero.
inline constexpr float kVoiceAgentTemperature = RAC_DEFAULT_VOICE_AGENT_TEMPERATURE;
inline constexpr int32_t kVoiceAgentTopK = 1;
inline constexpr int64_t kVoiceAgentSeed = 1;
inline constexpr const char* kVoiceAgentEmptyResponseMessage =
    "LLM generated no speakable response";
/// Retained flattened history entries (user+assistant), i.e. the most recent
/// N/2 turns.
inline constexpr size_t kVoiceAgentMaxHistoryEntries = 20;

struct VoiceConversationTurn {
    std::string user_text;
    std::string assistant_text;
};

/// Energy-VAD utterance segmenter state for the streaming
/// `rac_voice_agent_feed_audio_proto` ingress path. The SDK feeds raw mic
/// frames; this state accumulates them into utterances using the same
/// energy/noise-floor endpointing the Swift/Kotlin mic drivers used to run
/// per-SDK. PCM is 16 kHz mono S16LE (bytes are little-endian int16).
struct rac_voice_agent_feed_state {
    /// Leftover bytes that did not fill a whole analysis frame; prepended to
    /// the next feed call's audio.
    std::vector<uint8_t> frame_accum;
    /// Recent pre-speech frames retained so an utterance's onset is not
    /// clipped (mirrors the SDK pre-roll).
    std::deque<std::vector<uint8_t>> pre_roll;
    /// Accumulated PCM16 bytes for the in-progress utterance.
    std::string utterance;
    bool in_speech{false};
    int speech_ms{0};
    int silence_ms{0};
    /// Adaptive ambient floor. Seeded to zero — "nothing observed yet" — so the
    /// first frames are judged against the absolute floor-of-the-floor and the
    /// floor then rises to whatever this room/mic actually delivers. It used to
    /// be seeded to the old absolute 0.015 gate, which made the effective
    /// threshold 0.033 (-29.6 dBFS) until a quieter frame arrived. Never reset
    /// across turns; only adapted while idle.
    float noise_floor{0.0f};
    /// Consecutive analysis frames whose level cleared the (boosted) gate while
    /// the agent's own reply was still audible. A barge-in has to survive a few
    /// frames because the mic is hearing the loudspeaker at the same time.
    int barge_in_frames{0};
    /// Frames observed since the current reply became audible. The barge-in
    /// detector stays disarmed for the first few of them while `echo_floor`
    /// learns how loud the agent is to its own microphone — arming immediately
    /// would let the reply's own onset, which arrives after a device-dependent
    /// output latency, read as an interruption.
    int echo_frames{0};
    /// Echo level observed while the agent's reply is audible. During that
    /// window the mic signal is dominated by the device's own loudspeaker, so
    /// this is a running estimate of "the agent hearing itself" — the thing a
    /// user's voice has to rise above for a barge-in to be real rather than
    /// feedback. Reset when the audible window closes.
    float echo_floor{0.0f};
    /// Consecutive milliseconds of frames whose level did not even reach the
    /// absolute floor-of-the-floor, i.e. the input is delivering essentially no
    /// signal (muted mic, wrong input device, dead capture graph). Ordinary
    /// room silence sits well above that floor, so this counts only genuinely
    /// dead input.
    int64_t silent_input_ms{0};
    /// Loudest frame seen during the current dead-input stretch, so the
    /// diagnostic can report what it actually measured.
    float silent_input_peak{0.0f};
    /// True once the dead-input diagnostic has been reported for the current
    /// stretch, so it is said once instead of every frame.
    bool silent_input_reported{false};
    /// Wall-clock instant the reply we last handed the SDK stops being audible,
    /// derived from that reply's own duration. 0 = no reply outstanding. A
    /// speech onset before this instant is the user talking over the agent,
    /// which is the one moment worth telling the SDK about immediately, because
    /// only the SDK can stop the speaker. An onset after it is an ordinary new
    /// turn — which is what a half-duplex driver, silent for the whole playout,
    /// always produces.
    int64_t reply_audible_until_ms{0};
    /// Serializes feed-call segmentation; the heavy turn pipeline runs
    /// outside this lock so concurrent feeds only contend on buffering.
    std::mutex mutex;
};

/// Stage owned by the currently executing voice turn. Cancellation reads this
/// under `rac_voice_agent_turn_cancellation_state::mutex` so it only forwards
/// an interrupt to the modality that belongs to the matching turn.
enum class rac_voice_agent_turn_stage {
    none,
    vad,
    stt,
    llm,
    tts,
};

/// Request-scoped cancellation state for `rac_voice_agent_process_turn_proto`.
///
/// A cancelled request id is retained until its turn scope exits. This keeps a
/// cancel that wins the race with worker-isolate startup from being lost, while
/// a later turn with a different request id never inherits stale cancellation.
/// The set is bounded for callers that cancel an id which never starts.
struct rac_voice_agent_turn_cancellation_state {
    std::mutex mutex;
    std::condition_variable interrupt_finished;
    std::unordered_set<std::string> cancelled_request_ids;
    std::deque<std::string> cancellation_order;
    std::string active_request_id;
    std::string interrupt_request_id;
    rac_voice_agent_turn_stage active_stage{rac_voice_agent_turn_stage::none};
    bool backend_started{false};
};

struct rac_voice_agent {
    /// Set true when initialize* has run successfully. Atomic so
    /// `is_ready()` checks don't need the mutex.
    std::atomic<bool> is_configured{false};

    /// Shutdown barrier — destroy() waits for in-flight lock-free ops
    /// (e.g. `detect_speech`) to drain before tearing the agent down.
    std::atomic<bool> is_shutting_down{false};
    std::atomic<int> in_flight{0};

    rac_handle_t llm_handle{nullptr};
    rac_handle_t stt_handle{nullptr};
    rac_handle_t tts_handle{nullptr};
    rac_handle_t vad_handle{nullptr};

    /// Protects mutable operations (load, process, cleanup).
    std::mutex mutex;

    /// Streaming-ingress segmenter state (rac_voice_agent_feed_audio_proto).
    rac_voice_agent_feed_state feed;

    /// Lock-independent, request-scoped turn cancellation. This must remain
    /// separate from `mutex`: the executing turn holds `mutex` across the
    /// blocking STT -> LLM -> TTS pipeline, while another thread must be able
    /// to request cancellation immediately.
    rac_voice_agent_turn_cancellation_state turn_cancellation;

    /// Multi-turn conversation history for the LLM in chronological order
    /// (excludes the system prompt + current turn). Flattened into
    /// rac_llm_options_t.history as alternating user/assistant strings so the
    /// agent remembers context across turns. Bounded to the last
    /// kVoiceAgentMaxHistoryEntries flattened entries. Guarded by `mutex`.
    std::vector<VoiceConversationTurn> conversation_history;

    /// Monotonic 0-based turn counter for this agent, stamped onto each turn's
    /// telemetry (voice_telemetry.turn_index). Atomic so it can be read without
    /// holding `mutex`.
    std::atomic<int32_t> turn_counter{0};
};

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
