// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_pipeline.hpp — GAP 05 Phase 2 consumer #1.
//
// Internal C++ class that rebuilds the voice agent's request→response
// pipeline as a `rac::graph::GraphScheduler`-driven DAG:
//
//      InputSource ─▶ VAD ─▶ STT ─▶ LLM ─▶ TTS ─▶ Sink
//
// Each stage is a concrete subclass of `PipelineNode<In, Out>` with
// typed edges. Scheduler owns one worker thread per node; bounded
// `StreamEdge` buffers between nodes give us natural backpressure.
// `cancel_all()` propagates through the root CancelToken to every
// node within ~50 ms.
//
// Public C ABI is unchanged. This file is internal; it is NOT exported
// from `include/rac/`.
//
// Threading
// ---------
// `run_once()` is the request-driven entry point used by
// `rac_voice_agent_process_stream()`. It builds the graph, pushes one
// audio frame, drains terminal events back to the registered callback,
// and tears the graph down before returning. Concurrent callers are
// serialized by the agent's outer mutex; this class adds a per-instance
// mutex as belt-and-braces protection.
//
// Cancellation
// ------------
// The companion `cancel()` method is wired into the agent's destroy /
// cleanup path so an in-flight pipeline run is torn down deterministically
// when the agent shuts down. It is a non-blocking no-op when no run is
// in flight.

#pragma once

#include <atomic>
#include <memory>
#include <mutex>

#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/graph/cancel_token.hpp"

namespace rac::graph {
class GraphScheduler;
}  // namespace rac::graph

namespace rac::voice_agent {

class VoiceAgentPipeline {
public:
    /// `agent` owns the component handles the nodes call into. The
    /// pipeline does not take ownership; the caller (the agent) must
    /// outlive every active run_once() invocation.
    VoiceAgentPipeline(rac_voice_agent_handle_t          agent,
                       rac_voice_agent_event_callback_fn cb,
                       void*                             user_data);

    ~VoiceAgentPipeline();

    VoiceAgentPipeline(const VoiceAgentPipeline&)            = delete;
    VoiceAgentPipeline& operator=(const VoiceAgentPipeline&) = delete;

    /// Build the DAG, push the audio buffer, drain events to the
    /// registered callback, then tear down. Returns the first non-success
    /// status produced by any stage, or RAC_SUCCESS.
    rac_result_t run_once(const void* audio_data, size_t audio_size);

    /// Force-cancel any active run. Idempotent. Callable from any thread.
    /// Used by the agent destroy / cleanup paths to guarantee shutdown
    /// does not deadlock on a stalled stage.
    void cancel();

private:
    rac_voice_agent_handle_t                  agent_;
    rac_voice_agent_event_callback_fn         cb_;
    void*                                     user_data_;

    /// Serializes run_once(); the agent already holds an outer mutex so
    /// this is defense-in-depth.
    std::mutex                                run_mutex_;

    /// Set during run_once() so cancel() can reach the live graph.
    /// Reset to nullptr on return; protected by `state_mutex_`.
    std::mutex                                state_mutex_;
    std::shared_ptr<rac::graph::GraphScheduler> active_scheduler_;
    std::shared_ptr<rac::graph::CancelToken>    active_cancel_;
};

}  // namespace rac::voice_agent
