// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Concrete VoiceAgent pipeline — mic → VAD → STT → LLM → SentenceDetector
// → TTS → AudioSink with a transactional barge-in boundary.
//
// Port of RCLI src/pipeline/orchestrator.h and FastVoice
// VoiceAI/src/pipeline/orchestrator.cpp, adapted to use L4 StreamEdge
// instead of raw std::mutex + std::condition_variable, and the v2
// PluginRegistry/EngineRouter instead of hard-coded engine selection.
//
// This pipeline is concrete by design — the general L4 DAG abstraction is
// extracted FROM this implementation only after Phase 0 gate passes.

#ifndef RA_CORE_VOICE_PIPELINE_H
#define RA_CORE_VOICE_PIPELINE_H

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../abi/ra_primitives.h"
#include "../graph/cancel_token.h"
#include "../graph/ring_buffer.h"
#include "../graph/stream_edge.h"
#include "../registry/plugin_registry.h"
#include "../router/engine_router.h"
#include "sentence_detector.h"
#include "text_sanitizer.h"

namespace ra::core {

struct VoiceAgentConfig {
    // Model IDs — resolved via the L3 router.
    std::string llm_model_id  = "qwen3-4b";
    std::string stt_model_id  = "whisper-base";
    std::string tts_model_id  = "kokoro";
    std::string vad_model_id  = "silero-v5";

    // Audio.
    int  sample_rate_hz       = 16000;
    int  chunk_ms             = 20;

    // Barge-in.
    bool enable_barge_in      = true;
    int  barge_in_threshold_ms = 200;

    // LLM.
    std::string system_prompt;
    int  max_context_tokens   = 4096;
    float temperature         = 0.7f;

    // UI.
    bool emit_partials        = true;
    bool emit_thoughts        = false;
};

// Emitted by VoiceAgentPipeline through an output StreamEdge that the C ABI
// layer serializes to proto3 VoiceEvent and forwards to the frontend.
struct VoiceAgentEvent {
    enum class Kind {
        kUserSaid,
        kAssistantToken,
        kAudio,
        kVAD,
        kInterrupted,
        kStateChange,
        kError,
        kMetrics,
    };

    Kind                          kind;
    std::string                   text;            // user_said / assistant_token
    bool                          is_final    = false;
    int                           token_kind  = 1; // answer=1, thought=2
    std::vector<float>            pcm;             // audio
    int                           sample_rate = 0;
    ra_vad_event_type_t           vad_type    = RA_VAD_EVENT_UNKNOWN;
    int                           error_code  = 0;
    std::string                   message;         // interrupted / error
};

class VoiceAgentPipeline {
public:
    VoiceAgentPipeline(VoiceAgentConfig      cfg,
                       PluginRegistry&       registry,
                       EngineRouter&         router);
    ~VoiceAgentPipeline();

    VoiceAgentPipeline(const VoiceAgentPipeline&)            = delete;
    VoiceAgentPipeline& operator=(const VoiceAgentPipeline&) = delete;
    VoiceAgentPipeline(VoiceAgentPipeline&&)                 = delete;
    VoiceAgentPipeline& operator=(VoiceAgentPipeline&&)      = delete;

    // Start all operator threads. Non-blocking.
    ra_status_t start();

    // Request cancellation. Thread-safe. After this call, the output edge
    // closes and the completion callback (if set) fires.
    ra_status_t stop();

    // External feed — used when the config specifies callback-driven audio
    // (SolutionsProto AUDIO_SOURCE_CALLBACK). No-op when the mic source is
    // platform native.
    ra_status_t feed_audio(const float* pcm_f32, int num_samples, int sample_rate_hz);

    // Barge-in — transactional cancel boundary. Called from VAD when new
    // user speech is detected while the assistant is still synthesizing.
    //   1. set barge_in_flag_ (atomic)
    //   2. cancel LLM decode
    //   3. drain TTS ring buffer
    //   4. clear sentence queue
    // Called ONLY from the VAD thread (enforced by the scheduler).
    void on_barge_in();

    // Output stream the C ABI layer drains. Events are serialized to proto3
    // VoiceEvent on the boundary. Thread-safe.
    StreamEdge<VoiceAgentEvent>& output_stream() noexcept { return output_; }

    const std::shared_ptr<CancelToken>& cancel_token() const noexcept {
        return cancel_;
    }

private:
    // Thread bodies.
    void mic_capture_loop();
    void vad_loop();
    void stt_loop();
    void llm_loop();
    void sentence_emitter_loop();
    void tts_loop();
    void audio_sink_loop();

    VoiceAgentConfig  cfg_;
    PluginRegistry&   registry_;
    EngineRouter&     router_;

    // Plugin handles — resolved at construction.
    const PluginHandle* llm_plugin_ = nullptr;
    const PluginHandle* stt_plugin_ = nullptr;
    const PluginHandle* tts_plugin_ = nullptr;
    const PluginHandle* vad_plugin_ = nullptr;

    // Engine sessions.
    ra_llm_session_t*   llm_session_ = nullptr;
    ra_stt_session_t*   stt_session_ = nullptr;
    ra_tts_session_t*   tts_session_ = nullptr;
    ra_vad_session_t*   vad_session_ = nullptr;

    // Shared state — accessed from multiple threads.
    std::shared_ptr<CancelToken> cancel_;
    std::atomic<bool>            barge_in_flag_{false};
    std::atomic<bool>            started_{false};

    // L4 edges. feed_audio() tees each PCM frame to BOTH vad_audio_edge_
    // and stt_audio_edge_ so VAD and STT each get a complete copy — a single
    // edge would be drained by whichever worker popped first, causing
    // nondeterministic frame splitting between VAD and STT.
    StreamEdge<std::vector<float>>        vad_audio_edge_{64};   // mic -> vad
    StreamEdge<std::vector<float>>        stt_audio_edge_{64};   // mic -> stt
    StreamEdge<std::string>               transcript_edge_{16};  // stt -> llm
    StreamEdge<std::string>               token_edge_{256};      // llm -> sentence_detector
    StreamEdge<std::string>               sentence_edge_{32};    // sentence_detector -> tts
    StreamEdge<std::vector<float>>        audio_out_edge_{64};   // tts -> audio sink
    StreamEdge<VoiceAgentEvent>           output_{128};          // all events -> ABI

    // Playback ring buffer — drained by audio sink, filled by tts worker.
    // Size = ~2 seconds at 48 kHz.
    RingBuffer<float>                     playback_rb_{96000};

    // Sentence stream helper.
    SentenceDetector sentence_detector_;
    TextSanitizer    text_sanitizer_;

    // Threads — owned lifetime = pipeline lifetime.
    std::vector<std::thread>              threads_;

    // For barge-in coordination.
    std::mutex                            barge_in_mu_;
};

}  // namespace ra::core

#endif  // RA_CORE_VOICE_PIPELINE_H
