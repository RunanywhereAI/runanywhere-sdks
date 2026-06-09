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
#include <mutex>

#include "rac/core/rac_types.h"

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
};

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
