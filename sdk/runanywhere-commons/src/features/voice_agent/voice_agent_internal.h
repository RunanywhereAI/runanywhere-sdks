/**
 * @file voice_agent_internal.h
 * @brief Internal layout of `rac_voice_agent` shared between
 *        `voice_agent.cpp` and `voice_agent_pipeline.cpp`.
 *
 * NOT part of the public C ABI; do NOT include from anything under
 * `include/rac/`. Only the implementation files inside
 * `src/features/voice_agent/` may include this header.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
#define RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H

#include <atomic>
#include <memory>
#include <mutex>

#include "rac/core/rac_types.h"

namespace rac::voice_agent {
class VoiceAgentPipeline;
}  // namespace rac::voice_agent

struct rac_voice_agent {
    /// Set true when initialize* has run successfully. Atomic so
    /// `is_ready()` checks don't need the mutex.
    std::atomic<bool> is_configured{false};

    /// Shutdown barrier — destroy() waits for in-flight lock-free ops
    /// (e.g. `detect_speech`) to drain before tearing the agent down.
    std::atomic<bool> is_shutting_down{false};
    std::atomic<int>  in_flight{0};

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

    /// GAP 05 Phase 2: GraphScheduler-driven streaming pipeline. Lazily
    /// constructed when the first `process_stream()` call arrives so we
    /// don't pay the cost when the agent only services synchronous
    /// `process_voice_turn()` requests.
    ///
    /// Held via shared_ptr so destroy() can hand a reference to the
    /// in-flight cancel path without racing the agent destructor.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> pipeline;
};

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_H
