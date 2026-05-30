// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_pipeline.cpp
// See voice_agent_pipeline.hpp for the contract / threading notes.

#include "voice_agent_pipeline.hpp"

#include "rac_voice_event_abi_internal.h"
#include "voice_agent_internal.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "rac/audio/rac_audio_convert.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/graph/pipeline_node.hpp"
#include "rac/graph/stream_edge.hpp"

// Pipeline nodes prefer the global lifecycle
// bridge (level-1 impl + ops) so callers that loaded models via
// rac_model_lifecycle_load_proto / RunAnywhere.loadModel are served by the
// graph pipeline too. Fallback to the per-handle component preserves the
// legacy load path (rac_voice_agent_load_*_model). Mirrors the dispatch
// pattern used by rac_voice_agent_process_voice_turn_proto.
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"

namespace rac::voice_agent {

namespace {

// ---------------------------------------------------------------------------
// Edge payload types — each typed so the StreamEdge<T> bounded buffers give
// us natural backpressure across stage boundaries.
// ---------------------------------------------------------------------------

/// Owned audio frame. `run_once()` copies the caller's buffer into `bytes`
/// before pushing the frame onto the input edge, so the AudioFrame is safe
/// to read from any worker thread even if the caller's stack frame is torn
/// down or a future refactor reduces the outer-mutex hold time. The typical
/// 16 kHz int16 PCM utterance is <= ~32 KB so the copy is cheap relative
/// to the cost of running STT/LLM/TTS downstream.
struct AudioFrame {
    std::vector<uint8_t> bytes;
};

struct Transcript {
    std::string text;
};

struct Response {
    std::string text;
};

/// Result of TTS synthesis converted to WAV bytes (owned by the producer).
struct SynthesizedAudio {
    std::vector<uint8_t> wav;
};

/// Terminal sink event aggregator — the TTS node hands its final outputs
/// to the sink, which composes the `RAC_VOICE_AGENT_EVENT_PROCESSED` event
/// on the pipeline coordinator thread.
struct ProcessedPayload {
    std::string transcription;
    std::string response;
    std::vector<uint8_t> wav;
};

// ---------------------------------------------------------------------------
// Thread-safe event dispatcher — funnels every per-stage event through one
// mutex so callback observers see ordered, non-overlapping invocations.
// Mirrors the behaviour the legacy in-line orchestration provided implicitly
// (it held the outer agent mutex for the whole run).
// ---------------------------------------------------------------------------

class EventDispatcher {
   public:
    EventDispatcher(rac_voice_agent_handle_t agent, rac_voice_agent_event_callback_fn cb,
                    void* user_data) noexcept
        : agent_(agent), cb_(cb), user_data_(user_data) {}

    void emit(const rac_voice_agent_event_t& event) {
        std::lock_guard<std::mutex> lock(mu_);
        if (cb_)
            cb_(&event, user_data_);
        rac::voice_agent::dispatch_proto_event(agent_, &event);
    }

    /// Record the first non-success result observed; later errors are
    /// shadowed so the caller still gets the original failure mode.
    void record_error(rac_result_t code) {
        rac_result_t expected = RAC_SUCCESS;
        first_error_.compare_exchange_strong(expected, code, std::memory_order_acq_rel,
                                             std::memory_order_relaxed);
    }

    rac_result_t first_error() const noexcept {
        return first_error_.load(std::memory_order_acquire);
    }

    /// Convenience: emit RAC_VOICE_AGENT_EVENT_ERROR + record.
    void emit_error(rac_result_t code) {
        record_error(code);
        rac_voice_agent_event_t ev = {};
        ev.type = RAC_VOICE_AGENT_EVENT_ERROR;
        ev.data.error_code = code;
        emit(ev);
    }

   private:
    rac_voice_agent_handle_t agent_;
    rac_voice_agent_event_callback_fn cb_;
    void* user_data_;
    std::mutex mu_;
    std::atomic<rac_result_t> first_error_{RAC_SUCCESS};
};

// ---------------------------------------------------------------------------
// VAD gate — runs the agent's VAD component over the buffer and emits
// `RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED`. Always forwards the frame so the
// downstream STT stage transcribes it (matches legacy behaviour where STT
// ran unconditionally; VAD output was advisory in the streaming path).
// ---------------------------------------------------------------------------

class VADGateNode : public rac::graph::PipelineNode<AudioFrame, AudioFrame> {
   public:
    VADGateNode(rac_handle_t vad_handle, EventDispatcher& dispatcher)
        : PipelineNode("VAD", /*input*/ 4, /*output*/ 4),
          vad_(vad_handle),
          dispatcher_(dispatcher) {}

   protected:
    void process(AudioFrame frame, OutputEdge& out) override {
        // VAD expects float32 PCM at 16kHz. The voice-agent ABI contract
        // (rac_voice_agent_process_stream / VoiceAgentPipeline::run_once)
        // is int16 PCM at 16 kHz mono; non-int16-aligned buffers cannot be
        // VAD-processed and are surfaced as RAC_ERROR_INVALID_FORMAT
        // rather than silently skipped, so callers passing the wrong
        // format (e.g. raw float32 WebAudio buffers) get a deterministic
        // failure instead of bogus speech-detection results.
        const size_t bytes = frame.bytes.size();
        if (vad_ && bytes >= 2 && (bytes % sizeof(int16_t)) == 0) {
            const int16_t* pcm = reinterpret_cast<const int16_t*>(frame.bytes.data());
            const size_t count = bytes / sizeof(int16_t);
            std::vector<float> floats(count);
            // Route through the shared helper so any future
            // tuning (SIMD path, saturating clamp) applies here too.
            rac::audio::rac_audio_pcm16_to_float32(pcm, count, floats.data());
            rac_bool_t is_speech = RAC_FALSE;
            (void)rac_vad_component_process(vad_, floats.data(), count, &is_speech);

            rac_voice_agent_event_t ev = {};
            ev.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
            ev.data.vad_speech_active = is_speech;
            dispatcher_.emit(ev);
        } else if (vad_) {
            // Buffer is empty / odd / not int16-aligned. Bail out with an
            // explicit error instead of dispatching a phantom non-speech
            // VAD event followed by STT-on-garbage downstream.
            dispatcher_.emit_error(RAC_ERROR_INVALID_FORMAT);
            return;
        } else {
            // No VAD component configured — emit a non-speech advisory so
            // the downstream STT stage still runs (preserves the legacy
            // "always emit transcription" contract).
            rac_voice_agent_event_t ev = {};
            ev.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
            ev.data.vad_speech_active = RAC_FALSE;
            dispatcher_.emit(ev);
        }

        // Forward frame regardless — STT must still attempt transcription
        // so the legacy ABI's "always emit transcription" contract holds.
        out.push(std::move(frame), this->cancel_token());
    }

   private:
    rac_handle_t vad_;
    EventDispatcher& dispatcher_;
};

// ---------------------------------------------------------------------------
// STT — owned audio frame → transcript text.
// ---------------------------------------------------------------------------

class STTNode : public rac::graph::PipelineNode<AudioFrame, Transcript> {
   public:
    STTNode(rac_handle_t stt_handle, EventDispatcher& dispatcher)
        : PipelineNode("STT", /*input*/ 4, /*output*/ 4),
          stt_(stt_handle),
          dispatcher_(dispatcher) {}

   protected:
    void process(AudioFrame frame, OutputEdge& out) override {
        // Prefer the canonical lifecycle STT
        // ref so callers that loaded models via the lifecycle bridge are
        // served by the pipeline. Fall back to the per-handle component
        // for legacy load paths.
        rac::lifecycle::LifecycleSttRef ref{};
        const bool have_lifecycle = rac::lifecycle::acquire_lifecycle_stt(&ref) == RAC_SUCCESS;
        rac_stt_result_t r = {};
        rac_result_t status;
        const void* data = frame.bytes.data();
        const size_t size = frame.bytes.size();
        if (have_lifecycle) {
            rac_stt_service_t service{ref.ops, ref.impl, ref.model_id};
            status = rac_stt_transcribe(&service, data, size, nullptr, &r);
        } else {
            status = rac_stt_component_transcribe(stt_, data, size, nullptr, &r);
        }
        if (have_lifecycle) {
            rac::lifecycle::release_lifecycle_stt(&ref);
        }
        if (status != RAC_SUCCESS) {
            dispatcher_.emit_error(status);
            return;
        }

        rac_voice_agent_event_t ev = {};
        ev.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
        ev.data.transcription = r.text;
        dispatcher_.emit(ev);

        Transcript t{r.text ? std::string(r.text) : std::string()};
        rac_stt_result_free(&r);
        out.push(std::move(t), this->cancel_token());
    }

   private:
    rac_handle_t stt_;
    EventDispatcher& dispatcher_;
};

// ---------------------------------------------------------------------------
// LLM — transcript → response text.
// ---------------------------------------------------------------------------

class LLMNode : public rac::graph::PipelineNode<Transcript, Response> {
   public:
    LLMNode(rac_handle_t llm_handle, EventDispatcher& dispatcher)
        : PipelineNode("LLM", /*input*/ 4, /*output*/ 4),
          llm_(llm_handle),
          dispatcher_(dispatcher) {}

   protected:
    void process(Transcript prompt, OutputEdge& out) override {
        // Prefer lifecycle LLM ref with
        // per-handle fallback.
        rac::llm::LifecycleLlmRef ref{};
        const bool have_lifecycle = rac::llm::acquire_lifecycle_llm(&ref) == RAC_SUCCESS;
        rac_llm_result_t r = {};
        rac_result_t status;
        if (have_lifecycle) {
            rac_llm_service_t service{ref.ops, ref.impl, ref.model_id};
            status = rac_llm_generate(&service, prompt.text.c_str(), nullptr, &r);
        } else {
            status = rac_llm_component_generate(llm_, prompt.text.c_str(), nullptr, &r);
        }
        if (have_lifecycle) {
            rac::llm::release_lifecycle_llm(&ref);
        }
        if (status != RAC_SUCCESS) {
            dispatcher_.emit_error(status);
            return;
        }

        rac_voice_agent_event_t ev = {};
        ev.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
        ev.data.response = r.text;
        dispatcher_.emit(ev);

        Response resp{r.text ? std::string(r.text) : std::string()};
        rac_llm_result_free(&r);
        out.push(std::move(resp), this->cancel_token());
    }

   private:
    rac_handle_t llm_;
    EventDispatcher& dispatcher_;
};

// ---------------------------------------------------------------------------
// TTS — response text → synthesized WAV. Also publishes the AUDIO_SYNTHESIZED
// event and feeds the terminal sink so it can compose the PROCESSED event
// with all upstream payloads.
// ---------------------------------------------------------------------------

class TTSNode : public rac::graph::PipelineNode<Response, ProcessedPayload> {
   public:
    TTSNode(rac_handle_t tts_handle, EventDispatcher& dispatcher,
            std::shared_ptr<std::string> last_transcription)
        : PipelineNode("TTS", /*input*/ 4, /*output*/ 4),
          tts_(tts_handle),
          dispatcher_(dispatcher),
          last_transcription_(std::move(last_transcription)) {}

   protected:
    void process(Response resp, OutputEdge& out) override {
        // Prefer lifecycle TTS ref with
        // per-handle fallback.
        rac::lifecycle::LifecycleTtsRef ref{};
        const bool have_lifecycle = rac::lifecycle::acquire_lifecycle_tts(&ref) == RAC_SUCCESS;
        rac_tts_result_t r = {};
        rac_result_t status;
        if (have_lifecycle) {
            rac_tts_service_t service{ref.ops, ref.impl, ref.model_id};
            status = rac_tts_synthesize(&service, resp.text.c_str(), nullptr, &r);
        } else {
            status = rac_tts_component_synthesize(tts_, resp.text.c_str(), nullptr, &r);
        }
        if (have_lifecycle) {
            rac::lifecycle::release_lifecycle_tts(&ref);
        }
        if (status != RAC_SUCCESS) {
            dispatcher_.emit_error(status);
            return;
        }

        std::vector<uint8_t> wav;
        if (r.audio_data != nullptr && r.audio_size > 0) {
            void* raw_wav = nullptr;
            size_t raw_size = 0;
            const int sr = r.sample_rate > 0 ? r.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE;
            status = rac_audio_float32_to_wav(r.audio_data, r.audio_size, sr, &raw_wav, &raw_size);
            if (status != RAC_SUCCESS) {
                rac_tts_result_free(&r);
                dispatcher_.emit_error(status);
                return;
            }
            wav.assign(static_cast<uint8_t*>(raw_wav), static_cast<uint8_t*>(raw_wav) + raw_size);
            std::free(raw_wav);
        }

        // Emit the per-stage AUDIO_SYNTHESIZED event with the WAV bytes.
        rac_voice_agent_event_t ev = {};
        ev.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
        ev.data.audio.audio_data = wav.empty() ? nullptr : wav.data();
        ev.data.audio.audio_size = wav.size();
        dispatcher_.emit(ev);

        rac_tts_result_free(&r);

        ProcessedPayload payload;
        payload.transcription = last_transcription_ ? *last_transcription_ : std::string();
        payload.response = std::move(resp.text);
        payload.wav = std::move(wav);
        out.push(std::move(payload), this->cancel_token());
    }

   private:
    rac_handle_t tts_;
    EventDispatcher& dispatcher_;
    std::shared_ptr<std::string> last_transcription_;
};

// ---------------------------------------------------------------------------
// SinkNode — terminal stage. Composes the PROCESSED event mirroring the
// legacy in-line orchestration's final payload.
// ---------------------------------------------------------------------------

class SinkNode : public rac::graph::PipelineNode<ProcessedPayload, ProcessedPayload> {
   public:
    SinkNode(EventDispatcher& dispatcher)
        : PipelineNode("Sink", /*input*/ 4, /*output*/ 1), dispatcher_(dispatcher) {}

   protected:
    void process(ProcessedPayload payload, OutputEdge& out) override {
        // Each event-borne pointer is owned by `payload` (and lives until
        // we return from emit()); copies are made by the dispatcher's
        // proto translation path, and the legacy struct callback also
        // does not retain pointers past the call.
        char* trans_copy = nullptr;
        char* resp_copy = nullptr;
        if (!payload.transcription.empty()) {
            trans_copy = static_cast<char*>(std::malloc(payload.transcription.size() + 1));
            if (trans_copy) {
                std::memcpy(trans_copy, payload.transcription.data(), payload.transcription.size());
                trans_copy[payload.transcription.size()] = '\0';
            }
        }
        if (!payload.response.empty()) {
            resp_copy = static_cast<char*>(std::malloc(payload.response.size() + 1));
            if (resp_copy) {
                std::memcpy(resp_copy, payload.response.data(), payload.response.size());
                resp_copy[payload.response.size()] = '\0';
            }
        }
        void* wav_copy = nullptr;
        if (!payload.wav.empty()) {
            wav_copy = std::malloc(payload.wav.size());
            if (wav_copy) {
                std::memcpy(wav_copy, payload.wav.data(), payload.wav.size());
            }
        }

        rac_voice_agent_event_t ev = {};
        ev.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
        ev.data.result.speech_detected = RAC_TRUE;
        ev.data.result.transcription = trans_copy;
        ev.data.result.response = resp_copy;
        ev.data.result.synthesized_audio = wav_copy;
        ev.data.result.synthesized_audio_size = wav_copy ? payload.wav.size() : 0;
        dispatcher_.emit(ev);

        std::free(trans_copy);
        std::free(resp_copy);
        std::free(wav_copy);

        // Forward so the scheduler observes a clean drain.
        out.push(std::move(payload), this->cancel_token());
    }

   private:
    EventDispatcher& dispatcher_;
};

// ---------------------------------------------------------------------------
// Tap node — passively records the transcript into a shared string slot so
// the terminal sink can include it in the PROCESSED event without re-
// running STT. Keeps the LLM input edge typed correctly (Transcript→Resp).
// ---------------------------------------------------------------------------

class TranscriptTapNode : public rac::graph::PipelineNode<Transcript, Transcript> {
   public:
    TranscriptTapNode(std::shared_ptr<std::string> slot)
        : PipelineNode("Tap", /*input*/ 4, /*output*/ 4), slot_(std::move(slot)) {}

   protected:
    void process(Transcript t, OutputEdge& out) override {
        if (slot_)
            *slot_ = t.text;
        out.push(std::move(t), this->cancel_token());
    }

   private:
    std::shared_ptr<std::string> slot_;
};

}  // namespace

// ===========================================================================
// VoiceAgentPipeline
// ===========================================================================

VoiceAgentPipeline::VoiceAgentPipeline(rac_voice_agent_handle_t agent,
                                       rac_voice_agent_event_callback_fn cb, void* user_data)
    : agent_(agent), cb_(cb), user_data_(user_data) {}

VoiceAgentPipeline::~VoiceAgentPipeline() {
    cancel();
}

rac_result_t VoiceAgentPipeline::run_once(const void* audio_data, size_t audio_size) {
    if (!agent_)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> run_lock(run_mutex_);

    EventDispatcher dispatcher(agent_, cb_, user_data_);

    // Build the graph. Nodes are heap-allocated so the scheduler can hold
    // them via shared_ptr; the scheduler joins all worker threads in
    // wait() before we drop our local handles.
    auto scheduler = std::make_shared<rac::graph::GraphScheduler>(/*pool*/ 0);

    auto last_transcript = std::make_shared<std::string>();

    auto vad = std::make_shared<VADGateNode>(agent_->vad_handle, dispatcher);
    auto stt = std::make_shared<STTNode>(agent_->stt_handle, dispatcher);
    auto tap = std::make_shared<TranscriptTapNode>(last_transcript);
    auto llm = std::make_shared<LLMNode>(agent_->llm_handle, dispatcher);
    auto tts = std::make_shared<TTSNode>(agent_->tts_handle, dispatcher, last_transcript);
    auto sink = std::make_shared<SinkNode>(dispatcher);

    scheduler->add_node(vad);
    scheduler->add_node(stt);
    scheduler->add_node(tap);
    scheduler->add_node(llm);
    scheduler->add_node(tts);
    scheduler->add_node(sink);

    scheduler->connect(*vad, *stt);
    scheduler->connect(*stt, *tap);
    scheduler->connect(*tap, *llm);
    scheduler->connect(*llm, *tts);
    scheduler->connect(*tts, *sink);

    // Capture the input edge BEFORE start() so we can push the seed frame
    // without racing the worker's first pop. After start(), the worker
    // will block on pop() until we push.
    auto input_edge = vad->input();

    {
        std::lock_guard<std::mutex> state_lock(state_mutex_);
        active_scheduler_ = scheduler;
        active_cancel_ = scheduler->root_cancel_token();
    }

    scheduler->start();

    // Single-shot: copy the caller's audio into an owned AudioFrame
    // (removes the outer-mutex-coupled borrow), push it,
    // then close the input so each downstream stage observes EOF and the
    // graph drains naturally.
    AudioFrame frame;
    frame.bytes.assign(static_cast<const uint8_t*>(audio_data),
                       static_cast<const uint8_t*>(audio_data) + audio_size);
    input_edge->push(std::move(frame), scheduler->root_cancel_token().get());
    input_edge->close();

    scheduler->wait();

    {
        std::lock_guard<std::mutex> state_lock(state_mutex_);
        active_scheduler_.reset();
        active_cancel_.reset();
    }

    return dispatcher.first_error();
}

void VoiceAgentPipeline::cancel() {
    std::shared_ptr<rac::graph::GraphScheduler> sched;
    {
        std::lock_guard<std::mutex> state_lock(state_mutex_);
        sched = active_scheduler_;
    }
    if (sched) {
        sched->cancel_all();
    }
}

}  // namespace rac::voice_agent
