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
inline constexpr int32_t kVoiceAgentMaxTokens = 96;
/// Greedy decoding keeps a spoken turn stable and avoids sampling a verbose
/// continuation. A positive seed is also supplied for backends that still
/// construct a sampler when temperature is zero.
inline constexpr float kVoiceAgentTemperature = 0.0f;
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
    /// Adaptive ambient floor; seeded to the absolute speech threshold and
    /// never reset across turns (only adapted while idle).
    float noise_floor{0.015f};
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
