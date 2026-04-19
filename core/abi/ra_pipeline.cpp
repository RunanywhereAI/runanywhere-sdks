// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Bridges the struct-based pipeline C ABI onto the C++ VoiceAgentPipeline.
// No protobuf dependency — frontends construct ra_voice_agent_config_t
// directly and receive ra_voice_event_t structs via the callback.

#include "ra_pipeline.h"

#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../voice_pipeline/voice_pipeline.h"
#include "../registry/plugin_registry.h"
#include "../router/engine_router.h"
#include "../router/hardware_profile.h"

namespace {

using ra::core::VoiceAgentConfig;
using ra::core::VoiceAgentEvent;
using ra::core::VoiceAgentPipeline;

struct SessionBridge {
    std::unique_ptr<VoiceAgentPipeline>       pipeline;
    ra::core::HardwareProfile                 hw;
    std::unique_ptr<ra::core::EngineRouter>   router;

    ra_voice_event_callback_t event_cb{nullptr};
    void*                     event_ud{nullptr};
    ra_completion_callback_t  completion_cb{nullptr};
    void*                     completion_ud{nullptr};

    std::atomic<bool>         running{false};
    std::thread               consumer;

    ~SessionBridge() {
        if (pipeline) pipeline->stop();
        if (consumer.joinable()) consumer.join();
    }
};

VoiceAgentConfig translate(const ra_voice_agent_config_t& c) {
    VoiceAgentConfig cfg;
    if (c.llm_model_id && *c.llm_model_id) cfg.llm_model_id = c.llm_model_id;
    if (c.stt_model_id && *c.stt_model_id) cfg.stt_model_id = c.stt_model_id;
    if (c.tts_model_id && *c.tts_model_id) cfg.tts_model_id = c.tts_model_id;
    if (c.vad_model_id && *c.vad_model_id) cfg.vad_model_id = c.vad_model_id;
    if (c.sample_rate_hz > 0) cfg.sample_rate_hz = c.sample_rate_hz;
    if (c.chunk_ms > 0)       cfg.chunk_ms       = c.chunk_ms;
    cfg.enable_barge_in = c.enable_barge_in != 0;
    if (c.barge_in_threshold_ms > 0)
        cfg.barge_in_threshold_ms = c.barge_in_threshold_ms;
    if (c.system_prompt) cfg.system_prompt = c.system_prompt;
    if (c.max_context_tokens > 0) cfg.max_context_tokens = c.max_context_tokens;
    if (c.temperature > 0.0f)     cfg.temperature        = c.temperature;
    cfg.emit_partials = c.emit_partials != 0;
    cfg.emit_thoughts = c.emit_thoughts != 0;
    return cfg;
}

ra_pipeline_state_t map_state(int x) {
    // VoiceAgentPipeline today doesn't emit explicit state codes; default to IDLE.
    (void)x;
    return RA_PIPELINE_STATE_IDLE;
}

void fill_event(const VoiceAgentEvent& src, uint64_t seq,
                 ra_voice_event_t& dst) {
    std::memset(&dst, 0, sizeof(dst));
    dst.seq = seq;
    using K = VoiceAgentEvent::Kind;
    switch (src.kind) {
        case K::kUserSaid:
            dst.kind     = RA_VOICE_EVENT_USER_SAID;
            dst.text     = src.text.c_str();
            dst.is_final = src.is_final ? 1 : 0;
            break;
        case K::kAssistantToken:
            dst.kind       = RA_VOICE_EVENT_ASSISTANT_TOKEN;
            dst.text       = src.text.c_str();
            dst.is_final   = src.is_final ? 1 : 0;
            dst.token_kind = src.token_kind;
            break;
        case K::kAudio:
            dst.kind           = RA_VOICE_EVENT_AUDIO;
            dst.pcm_f32        = src.pcm.data();
            dst.pcm_len        = static_cast<int32_t>(src.pcm.size());
            dst.sample_rate_hz = src.sample_rate;
            break;
        case K::kVAD:
            dst.kind     = RA_VOICE_EVENT_VAD;
            dst.vad_type = src.vad_type;
            break;
        case K::kInterrupted:
            dst.kind = RA_VOICE_EVENT_INTERRUPTED;
            dst.text = src.message.c_str();
            break;
        case K::kStateChange:
            dst.kind       = RA_VOICE_EVENT_STATE_CHANGE;
            dst.prev_state = map_state(src.token_kind);
            dst.curr_state = map_state(src.error_code);
            break;
        case K::kError:
            dst.kind       = RA_VOICE_EVENT_ERROR;
            dst.text       = src.message.c_str();
            dst.error_code = src.error_code;
            break;
        case K::kMetrics:
            dst.kind = RA_VOICE_EVENT_METRICS;
            break;
    }
}

}  // namespace

struct ra_pipeline_s {
    std::unique_ptr<SessionBridge> bridge;
};

extern "C" {

ra_status_t ra_pipeline_create_voice_agent(
    const ra_voice_agent_config_t* config,
    ra_pipeline_t**                out_pipeline) {
    if (!config || !out_pipeline) return RA_ERR_INVALID_ARGUMENT;

    auto cfg = translate(*config);
    auto bridge = std::make_unique<SessionBridge>();
    bridge->hw     = ra::core::HardwareProfile::detect();
    bridge->router = std::make_unique<ra::core::EngineRouter>(
        ra::core::PluginRegistry::global(), bridge->hw);
    bridge->pipeline = std::make_unique<VoiceAgentPipeline>(
        cfg, ra::core::PluginRegistry::global(), *bridge->router);

    auto* handle = new ra_pipeline_s{std::move(bridge)};
    *out_pipeline = handle;
    return RA_OK;
}

void ra_pipeline_destroy(ra_pipeline_t* pipeline) {
    delete pipeline;
}

ra_status_t ra_pipeline_set_event_callback(ra_pipeline_t*            pipeline,
                                            ra_voice_event_callback_t callback,
                                            void*                     user_data) {
    if (!pipeline || !pipeline->bridge) return RA_ERR_INVALID_ARGUMENT;
    pipeline->bridge->event_cb = callback;
    pipeline->bridge->event_ud = user_data;
    return RA_OK;
}

ra_status_t ra_pipeline_set_completion_callback(
    ra_pipeline_t*           pipeline,
    ra_completion_callback_t callback,
    void*                    user_data) {
    if (!pipeline || !pipeline->bridge) return RA_ERR_INVALID_ARGUMENT;
    pipeline->bridge->completion_cb = callback;
    pipeline->bridge->completion_ud = user_data;
    return RA_OK;
}

ra_status_t ra_pipeline_run(ra_pipeline_t* pipeline) {
    if (!pipeline || !pipeline->bridge || !pipeline->bridge->pipeline)
        return RA_ERR_INVALID_ARGUMENT;
    if (pipeline->bridge->running.exchange(true)) return RA_OK;

    auto* bridge = pipeline->bridge.get();
    const auto status = bridge->pipeline->start();
    if (status != RA_OK) { bridge->running = false; return status; }

    bridge->consumer = std::thread([bridge]() {
        uint64_t seq = 0;
        auto& stream = bridge->pipeline->output_stream();
        while (true) {
            auto opt = stream.pop();
            if (!opt.has_value()) break;
            if (bridge->event_cb) {
                ra_voice_event_t ev;
                fill_event(*opt, ++seq, ev);
                bridge->event_cb(&ev, bridge->event_ud);
            }
        }
        if (bridge->completion_cb) {
            bridge->completion_cb(RA_OK, "", bridge->completion_ud);
        }
    });
    return RA_OK;
}

ra_status_t ra_pipeline_cancel(ra_pipeline_t* pipeline) {
    if (!pipeline || !pipeline->bridge || !pipeline->bridge->pipeline)
        return RA_ERR_INVALID_ARGUMENT;
    return pipeline->bridge->pipeline->stop();
}

ra_status_t ra_pipeline_feed_audio(ra_pipeline_t* pipeline,
                                    const float*   pcm_f32,
                                    int32_t        num_samples,
                                    int32_t        sample_rate_hz) {
    if (!pipeline || !pipeline->bridge || !pipeline->bridge->pipeline)
        return RA_ERR_INVALID_ARGUMENT;
    return pipeline->bridge->pipeline->feed_audio(pcm_f32, num_samples, sample_rate_hz);
}

ra_status_t ra_pipeline_inject_barge_in(ra_pipeline_t* pipeline) {
    if (!pipeline || !pipeline->bridge || !pipeline->bridge->pipeline)
        return RA_ERR_INVALID_ARGUMENT;
    pipeline->bridge->pipeline->on_barge_in();
    return RA_OK;
}

}  // extern "C"
