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
#include <deque>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_types.h"

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

struct rac_voice_agent {
    /// Set true when initialize* has run successfully. Atomic so
    /// `is_ready()` checks don't need the mutex.
    std::atomic<bool> is_configured{false};

    /// Shutdown barrier — destroy() waits for in-flight lock-free ops
    /// (e.g. `detect_speech`) to drain before tearing the agent down.
    std::atomic<bool> is_shutting_down{false};
    std::atomic<int> in_flight{0};

    /// True when the agent created its own component handles via
    /// `rac_voice_agent_create_standalone()`. The destructor frees them
    /// in reverse creation order.
    bool owns_components{false};

    rac_handle_t llm_handle{nullptr};
    rac_handle_t stt_handle{nullptr};
    rac_handle_t tts_handle{nullptr};
    rac_handle_t vad_handle{nullptr};

    /// Protects mutable operations (load, process, cleanup).
    std::mutex mutex;

    /// Streaming-ingress segmenter state (rac_voice_agent_feed_audio_proto).
    rac_voice_agent_feed_state feed;
};

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
