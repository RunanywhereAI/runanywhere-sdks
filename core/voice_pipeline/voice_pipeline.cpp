// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "voice_pipeline.h"

#include <algorithm>
#include <cstring>
#include <thread>
#include <utility>

namespace ra::core {

namespace {

// VoiceAgentEvent factory helpers — concise call sites in the worker loops.
VoiceAgentEvent make_user_said(std::string text, bool is_final) {
    VoiceAgentEvent e;
    e.kind     = VoiceAgentEvent::Kind::kUserSaid;
    e.text     = std::move(text);
    e.is_final = is_final;
    return e;
}

VoiceAgentEvent make_token(std::string tok, bool is_final, int kind) {
    VoiceAgentEvent e;
    e.kind       = VoiceAgentEvent::Kind::kAssistantToken;
    e.text       = std::move(tok);
    e.is_final   = is_final;
    e.token_kind = kind;
    return e;
}

VoiceAgentEvent make_audio(std::vector<float> pcm, int sr) {
    VoiceAgentEvent e;
    e.kind        = VoiceAgentEvent::Kind::kAudio;
    e.pcm         = std::move(pcm);
    e.sample_rate = sr;
    return e;
}

VoiceAgentEvent make_interrupted(std::string reason) {
    VoiceAgentEvent e;
    e.kind    = VoiceAgentEvent::Kind::kInterrupted;
    e.message = std::move(reason);
    return e;
}

VoiceAgentEvent make_error(int code, std::string msg) {
    VoiceAgentEvent e;
    e.kind       = VoiceAgentEvent::Kind::kError;
    e.error_code = code;
    e.message    = std::move(msg);
    return e;
}

}  // namespace

VoiceAgentPipeline::VoiceAgentPipeline(VoiceAgentConfig cfg,
                                        PluginRegistry&  registry,
                                        EngineRouter&    router)
    : cfg_(std::move(cfg)),
      registry_(registry),
      router_(router),
      cancel_(CancelToken::create()) {
    sentence_detector_.set_callback([this](std::string sentence) {
        // Drop sentences that were in-flight when barge-in fires.
        if (barge_in_flag_.load(std::memory_order_acquire)) return;
        sentence_edge_.push(std::move(sentence));
    });
}

VoiceAgentPipeline::~VoiceAgentPipeline() {
    stop();
    for (auto& t : threads_) {
        if (t.joinable()) t.join();
    }

    // Destroy engine sessions. Acquire-load each atomic pointer exactly
    // once; threads are already joined so no further publish can race us.
    if (auto* s = llm_session_.load(std::memory_order_acquire);
        s && llm_plugin_ && llm_plugin_->vtable.llm_destroy) {
        llm_plugin_->vtable.llm_destroy(s);
    }
    if (auto* s = stt_session_.load(std::memory_order_acquire);
        s && stt_plugin_ && stt_plugin_->vtable.stt_destroy) {
        stt_plugin_->vtable.stt_destroy(s);
    }
    if (auto* s = tts_session_.load(std::memory_order_acquire);
        s && tts_plugin_ && tts_plugin_->vtable.tts_destroy) {
        tts_plugin_->vtable.tts_destroy(s);
    }
    if (auto* s = vad_session_.load(std::memory_order_acquire);
        s && vad_plugin_ && vad_plugin_->vtable.vad_destroy) {
        vad_plugin_->vtable.vad_destroy(s);
    }
}

ra_status_t VoiceAgentPipeline::start() {
    bool expected = false;
    if (!started_.compare_exchange_strong(expected, true)) {
        return RA_ERR_INVALID_ARGUMENT;
    }

    // Route each operator to a capable engine. For MVP we pick
    // self-contained engines (llama.cpp for LLM, sherpa for STT/TTS/VAD).
    auto route = [&](ra_primitive_t prim, ra_model_format_t fmt) {
        RouteRequest req{prim, fmt, 0, {}};
        return router_.route(req).plugin;
    };

    llm_plugin_ = route(RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF);
    stt_plugin_ = route(RA_PRIMITIVE_TRANSCRIBE,    RA_FORMAT_ONNX);
    tts_plugin_ = route(RA_PRIMITIVE_SYNTHESIZE,    RA_FORMAT_ONNX);
    vad_plugin_ = route(RA_PRIMITIVE_DETECT_VOICE,  RA_FORMAT_ONNX);

    if (!llm_plugin_) { output_.push(make_error(RA_ERR_BACKEND_UNAVAILABLE,
        "no LLM engine registered for generate_text/GGUF")); return RA_ERR_BACKEND_UNAVAILABLE; }
    if (!stt_plugin_) { output_.push(make_error(RA_ERR_BACKEND_UNAVAILABLE,
        "no STT engine registered for transcribe/ONNX")); return RA_ERR_BACKEND_UNAVAILABLE; }
    if (!tts_plugin_) { output_.push(make_error(RA_ERR_BACKEND_UNAVAILABLE,
        "no TTS engine registered for synthesize/ONNX")); return RA_ERR_BACKEND_UNAVAILABLE; }
    if (!vad_plugin_) { output_.push(make_error(RA_ERR_BACKEND_UNAVAILABLE,
        "no VAD engine registered for detect_voice/ONNX")); return RA_ERR_BACKEND_UNAVAILABLE; }

    threads_.emplace_back([this] { vad_loop(); });
    threads_.emplace_back([this] { stt_loop(); });
    threads_.emplace_back([this] { llm_loop(); });
    threads_.emplace_back([this] { sentence_emitter_loop(); });
    threads_.emplace_back([this] { tts_loop(); });
    threads_.emplace_back([this] { audio_sink_loop(); });
    return RA_OK;
}

ra_status_t VoiceAgentPipeline::stop() {
    cancel_->cancel();
    vad_audio_edge_.close();
    stt_audio_edge_.close();
    transcript_edge_.close();
    token_edge_.close();
    sentence_edge_.close();
    audio_out_edge_.close();
    output_.close();
    return RA_OK;
}

ra_status_t VoiceAgentPipeline::feed_audio(const float* pcm,
                                            int          num_samples,
                                            int          sample_rate_hz) {
    if (!pcm || num_samples <= 0) return RA_ERR_INVALID_ARGUMENT;
    (void)sample_rate_hz;  // For MVP, caller ensures cfg_.sample_rate_hz matches.

    // Tee the frame to BOTH consumers — StreamEdge::pop() is single-consumer
    // (removes items), so publishing to only one edge would nondeterministically
    // starve either VAD (breaking barge-in detection) or STT (breaking
    // transcription). Two independent copies keep both pipelines hot.
    std::vector<float> for_vad(pcm, pcm + num_samples);
    std::vector<float> for_stt = for_vad;

    auto rc_vad = vad_audio_edge_.push(std::move(for_vad));
    auto rc_stt = stt_audio_edge_.push(std::move(for_stt));
    if (rc_vad != PushResult::kOk || rc_stt != PushResult::kOk) {
        return RA_ERR_CANCELLED;
    }
    return RA_OK;
}

// --- Barge-in — the transactional cancel boundary ---------------------------
//
// MUST run to completion without interruption:
//   1. set the atomic flag (producers check before enqueue)
//   2. cancel the LLM decode loop
//   3. drain the TTS playback ring buffer (audio sink will receive silence)
//   4. clear the sentence queue (TTS worker will see barge_in_flag_ and break)
//
// Any in-flight token produced after the flag is set is still free to arrive
// at the SentenceDetector, but the SentenceDetector callback drops tokens
// when the flag is set.
void VoiceAgentPipeline::on_barge_in() {
    std::lock_guard<std::mutex> lk(barge_in_mu_);
    barge_in_flag_.store(true, std::memory_order_release);

    // Acquire-load the session pointer. llm_loop's release-store is the
    // matching side of this happens-before edge.
    if (auto* s = llm_session_.load(std::memory_order_acquire);
        s && llm_plugin_ && llm_plugin_->vtable.llm_cancel) {
        llm_plugin_->vtable.llm_cancel(s);
    }
    playback_rb_.drain();
    sentence_edge_.clear_locked();

    output_.push(make_interrupted("user barge-in"));
}

// --- Worker loops -----------------------------------------------------------
//
// These are thin, predictable loops. Each one:
//   * consumes from one or more input edges
//   * produces to output edge(s)
//   * checks cancel_->is_cancelled() before blocking
//   * exits cleanly on close / cancel

void VoiceAgentPipeline::vad_loop() {
    if (!vad_plugin_ || !vad_plugin_->vtable.vad_create) return;

    ra_model_spec_t spec{};
    spec.model_id = cfg_.vad_model_id.c_str();
    spec.format   = RA_FORMAT_ONNX;
    ra_session_config_t session_cfg{};

    ra_vad_session_t* local_vad = nullptr;
    auto rc = vad_plugin_->vtable.vad_create(&spec, &session_cfg, &local_vad);
    if (rc != RA_OK) {
        output_.push(make_error(rc, "VAD create failed"));
        return;
    }
    // Publish the handle atomically so on_barge_in and ~VoiceAgentPipeline
    // see a fully-constructed session.
    vad_session_.store(local_vad, std::memory_order_release);

    // Wire VAD callback so BARGE_IN triggers on_barge_in().
    if (vad_plugin_->vtable.vad_set_callback) {
        vad_plugin_->vtable.vad_set_callback(
            local_vad,
            [](const ra_vad_event_t* ev, void* ud) {
                auto* self = static_cast<VoiceAgentPipeline*>(ud);
                if (ev->type == RA_VAD_EVENT_BARGE_IN &&
                    self->cfg_.enable_barge_in) {
                    self->on_barge_in();
                }
                // Forward to UI.
                VoiceAgentEvent e;
                e.kind     = VoiceAgentEvent::Kind::kVAD;
                e.vad_type = ev->type;
                self->output_.push(std::move(e));
            },
            this);
    }

    while (!cancel_->is_cancelled()) {
        auto frame = vad_audio_edge_.pop();
        if (!frame) break;
        if (!vad_plugin_->vtable.vad_feed_audio) continue;
        vad_plugin_->vtable.vad_feed_audio(
            local_vad, frame->data(),
            static_cast<int>(frame->size()), cfg_.sample_rate_hz);
        // The same frame is also consumed by stt_loop via the shared edge.
    }
}

void VoiceAgentPipeline::stt_loop() {
    if (!stt_plugin_ || !stt_plugin_->vtable.stt_create) return;

    ra_model_spec_t spec{};
    spec.model_id = cfg_.stt_model_id.c_str();
    spec.format   = RA_FORMAT_ONNX;
    ra_session_config_t session_cfg{};

    ra_stt_session_t* local_stt = nullptr;
    auto rc = stt_plugin_->vtable.stt_create(&spec, &session_cfg, &local_stt);
    if (rc != RA_OK) {
        output_.push(make_error(rc, "STT create failed"));
        return;
    }
    stt_session_.store(local_stt, std::memory_order_release);

    if (stt_plugin_->vtable.stt_set_callback) {
        stt_plugin_->vtable.stt_set_callback(
            local_stt,
            [](const ra_transcript_chunk_t* chunk, void* ud) {
                auto* self = static_cast<VoiceAgentPipeline*>(ud);
                if (chunk->is_partial && !self->cfg_.emit_partials) return;
                self->output_.push(
                    make_user_said(chunk->text ? chunk->text : "",
                                    !chunk->is_partial));
                if (!chunk->is_partial) {
                    self->transcript_edge_.push(
                        chunk->text ? chunk->text : "");
                    // New utterance — clear any stale barge-in flag.
                    self->barge_in_flag_.store(false,
                                                std::memory_order_release);
                }
            },
            this);
    }

    // STT consumes its own copy of each frame via the dedicated
    // stt_audio_edge_ that feed_audio() tees into. VAD gets the mirror edge.
    while (!cancel_->is_cancelled()) {
        auto frame = stt_audio_edge_.pop();
        if (!frame) break;
        if (!stt_plugin_->vtable.stt_feed_audio) continue;
        stt_plugin_->vtable.stt_feed_audio(
            local_stt, frame->data(),
            static_cast<int>(frame->size()), cfg_.sample_rate_hz);
    }
}

void VoiceAgentPipeline::llm_loop() {
    if (!llm_plugin_ || !llm_plugin_->vtable.llm_create) return;

    ra_model_spec_t spec{};
    spec.model_id = cfg_.llm_model_id.c_str();
    spec.format   = RA_FORMAT_GGUF;
    ra_session_config_t session_cfg{};
    session_cfg.context_size = cfg_.max_context_tokens;

    ra_llm_session_t* local_llm = nullptr;
    auto rc = llm_plugin_->vtable.llm_create(&spec, &session_cfg, &local_llm);
    if (rc != RA_OK) {
        output_.push(make_error(rc, "LLM create failed"));
        return;
    }
    llm_session_.store(local_llm, std::memory_order_release);

    while (!cancel_->is_cancelled()) {
        auto prompt_text = transcript_edge_.pop();
        if (!prompt_text) break;

        ra_prompt_t prompt{};
        prompt.text            = prompt_text->c_str();
        prompt.conversation_id = 0;

        if (!llm_plugin_->vtable.llm_generate) continue;
        // The engine plugin calls this callback on its own decode thread.
        llm_plugin_->vtable.llm_generate(
            local_llm,
            &prompt,
            [](const ra_token_output_t* tok, void* ud) {
                auto* self = static_cast<VoiceAgentPipeline*>(ud);
                if (self->barge_in_flag_.load(std::memory_order_acquire)) {
                    return;
                }
                self->output_.push(make_token(tok->text ? tok->text : "",
                                               tok->is_final,
                                               tok->token_kind));
                self->token_edge_.push(tok->text ? tok->text : "");
                if (tok->is_final) {
                    self->token_edge_.push("");  // Sentinel: flush sentence.
                }
            },
            [](ra_status_t code, const char* msg, void* ud) {
                auto* self = static_cast<VoiceAgentPipeline*>(ud);
                self->output_.push(make_error(code, msg ? msg : ""));
            },
            this);
    }
}

void VoiceAgentPipeline::sentence_emitter_loop() {
    while (!cancel_->is_cancelled()) {
        auto tok = token_edge_.pop();
        if (!tok) break;
        if (tok->empty()) {
            sentence_detector_.flush();
            continue;
        }
        sentence_detector_.feed(*tok);
    }
    sentence_detector_.flush();
}

void VoiceAgentPipeline::tts_loop() {
    if (!tts_plugin_ || !tts_plugin_->vtable.tts_create) return;

    ra_model_spec_t spec{};
    spec.model_id = cfg_.tts_model_id.c_str();
    spec.format   = RA_FORMAT_ONNX;
    ra_session_config_t session_cfg{};

    ra_tts_session_t* local_tts = nullptr;
    auto rc = tts_plugin_->vtable.tts_create(&spec, &session_cfg, &local_tts);
    if (rc != RA_OK) {
        output_.push(make_error(rc, "TTS create failed"));
        return;
    }
    tts_session_.store(local_tts, std::memory_order_release);

    std::vector<float> pcm_buf(48000 * 10);  // 10 s scratch at 48 kHz
    while (!cancel_->is_cancelled()) {
        auto sentence = sentence_edge_.pop();
        if (!sentence) break;
        if (barge_in_flag_.load(std::memory_order_acquire)) continue;

        const std::string clean = text_sanitizer_.sanitize(*sentence);
        if (clean.empty()) continue;

        int32_t written = 0;
        int32_t sr      = 0;
        if (!tts_plugin_->vtable.tts_synthesize) continue;
        const ra_status_t st = tts_plugin_->vtable.tts_synthesize(
            local_tts, clean.c_str(),
            pcm_buf.data(), static_cast<int32_t>(pcm_buf.size()),
            &written, &sr);
        if (st != RA_OK || written <= 0) continue;

        if (barge_in_flag_.load(std::memory_order_acquire)) continue;

        std::vector<float> out(pcm_buf.data(), pcm_buf.data() + written);
        audio_out_edge_.push(out);
        output_.push(make_audio(std::move(out), sr));
    }
}

void VoiceAgentPipeline::audio_sink_loop() {
    while (!cancel_->is_cancelled()) {
        auto frame = audio_out_edge_.pop();
        if (!frame) break;
        // In production, this is where the audio sink engine writes to
        // the platform audio subsystem (AVAudioEngine/AAudio/WebAudio).
        // For MVP we rely on the frontend to consume the kAudio events.
        playback_rb_.push_n(frame->data(), frame->size());
    }
}

}  // namespace ra::core
