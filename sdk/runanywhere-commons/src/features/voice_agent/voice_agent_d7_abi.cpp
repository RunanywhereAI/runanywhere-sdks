/**
 * @file voice_agent_d7_abi.cpp
 * @brief Full-session voice-agent C ABI — proto-byte streaming
 *        path used by SDK frontends to drive a complete voice turn with
 *        session/turn/request correlation.
 *
 * Hosts the SDK-facing surface:
 *   - `rac_voice_agent_process_turn_proto`,
 *   - `rac_voice_agent_cancel_turn_proto`,
 *   - `rac_voice_agent_transcribe_proto`,
 *   - `rac_voice_agent_synthesize_speech_proto`,
 *   - `rac_voice_agent_component_create_proto`,
 *   - `rac_voice_agent_component_destroy_proto`,
 *   - and the d7_emit_* helpers used to fan a `VoiceEvent` out to (a) the
 *     per-call turn-event callback, (b) the per-handle proto callback
 *     registered via `rac_voice_agent_set_proto_callback`, and (c) the
 *     global SDKEvent publisher.
 */

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
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
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

#include "rac_voice_event_abi_internal.h"
#include "voice_agent_internal.h"
#include "voice_agent_internal_helpers.h"
#include "voice_agent_tts_chunking.h"

#if defined(RAC_HAVE_PROTOBUF)

namespace {

void d7_emit_voice_event(rac_voice_agent_handle_t handle, runanywhere::v1::VoiceEvent* event,
                         const std::string& session_id, const std::string& turn_id,
                         const std::string& request_id, rac_voice_agent_turn_event_callback_fn cb,
                         void* user_data) {
    if (!event)
        return;
    if (event->timestamp_us() == 0) {
        event->set_timestamp_us(rac_get_current_time_ms() * 1000);
    }
    if (!session_id.empty() && event->session_id().empty())
        event->set_session_id(session_id);
    if (!turn_id.empty() && event->turn_id().empty())
        event->set_turn_id(turn_id);
    if (!request_id.empty() && event->request_id().empty())
        event->set_request_id(request_id);

    if (cb) {
        const size_t size = event->ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size == 0 || event->SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            cb(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_data);
        }
    }
    rac::voice_agent::dispatch_proto_voice_event(handle, *event);
    rac::voice_agent::detail::publish_voice_pipeline_sdk_event(
        *event, event->severity() == runanywhere::v1::ERROR_SEVERITY_ERROR
                    ? runanywhere::v1::ERROR_SEVERITY_ERROR
                    : runanywhere::v1::ERROR_SEVERITY_INFO);
}

// Map a proto PipelineState to the C audio-pipeline-state enum used by
// rac_audio_pipeline_is_valid_transition. Returns RAC_AUDIO_PIPELINE_ERROR
// (the "any-target-is-valid" sink) for proto states that don't have a
// direct counterpart in the C enum, so we never spuriously reject a
// transition the C validator wasn't designed to cover.
rac_audio_pipeline_state_t d7_proto_state_to_audio_state(runanywhere::v1::PipelineState state) {
    switch (state) {
        case runanywhere::v1::PIPELINE_STATE_IDLE:
            return RAC_AUDIO_PIPELINE_IDLE;
        case runanywhere::v1::PIPELINE_STATE_LISTENING:
            return RAC_AUDIO_PIPELINE_LISTENING;
        case runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH:
            return RAC_AUDIO_PIPELINE_PROCESSING_SPEECH;
        case runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE:
            return RAC_AUDIO_PIPELINE_GENERATING_RESPONSE;
        case runanywhere::v1::PIPELINE_STATE_PLAYING_TTS:
            return RAC_AUDIO_PIPELINE_PLAYING_TTS;
        case runanywhere::v1::PIPELINE_STATE_COOLDOWN:
            return RAC_AUDIO_PIPELINE_COOLDOWN;
        case runanywhere::v1::PIPELINE_STATE_WAITING_WAKEWORD:
            return RAC_AUDIO_PIPELINE_WAITING_WAKEWORD;
        case runanywhere::v1::PIPELINE_STATE_ERROR:
            return RAC_AUDIO_PIPELINE_ERROR;
        default:
            return RAC_AUDIO_PIPELINE_ERROR;
    }
}

void d7_emit_state(rac_voice_agent_handle_t handle, runanywhere::v1::PipelineState previous,
                   runanywhere::v1::PipelineState current, const std::string& session_id,
                   const std::string& turn_id, const std::string& request_id,
                   rac_voice_agent_turn_event_callback_fn cb, void* user_data) {
    // Gate against the documented state machine
    // (rac_audio_pipeline_is_valid_transition). Invalid transitions still
    // emit so downstream subscribers see the desync, but we log a warning
    // so frontend authors notice when the pipeline takes an unsanctioned
    // shortcut (e.g. PLAYING_TTS -> IDLE skipping COOLDOWN).
    const rac_audio_pipeline_state_t from = d7_proto_state_to_audio_state(previous);
    const rac_audio_pipeline_state_t to = d7_proto_state_to_audio_state(current);
    if (rac_audio_pipeline_is_valid_transition(from, to) != RAC_TRUE) {
        RAC_LOG_WARNING("VoiceAgent",
                        "Invalid pipeline transition %s -> %s; emitting anyway for observability",
                        rac_audio_pipeline_state_name(from), rac_audio_pipeline_state_name(to));
    }

    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* s = event.mutable_state();
    s->set_previous(previous);
    s->set_current(current);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_vad(rac_voice_agent_handle_t handle, runanywhere::v1::VADStreamEventKind kind,
                 bool is_speech, const std::string& session_id, const std::string& turn_id,
                 const std::string& request_id, rac_voice_agent_turn_event_callback_fn cb,
                 void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VAD);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_VAD);
    auto* v = event.mutable_vad();
    v->set_type(kind);
    v->set_is_speech(is_speech);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_user_said(rac_voice_agent_handle_t handle, const char* text, const std::string& lang,
                       const std::string& session_id, const std::string& turn_id,
                       const std::string& request_id, rac_voice_agent_turn_event_callback_fn cb,
                       void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_STT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_STT);
    auto* u = event.mutable_user_said();
    if (text)
        u->set_text(text);
    u->set_is_final(true);
    if (!lang.empty())
        u->set_language_code(lang);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_assistant_token(rac_voice_agent_handle_t handle, const char* text, bool is_final,
                             runanywhere::v1::TokenKind kind, const std::string& session_id,
                             const std::string& turn_id, const std::string& request_id,
                             rac_voice_agent_turn_event_callback_fn cb, void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_LLM);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_LLM);
    auto* t = event.mutable_assistant_token();
    if (text)
        t->set_text(text);
    t->set_is_final(is_final);
    t->set_kind(kind);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_audio(rac_voice_agent_handle_t handle, const void* data, size_t size,
                   int32_t sample_rate, bool is_final, const std::string& session_id,
                   const std::string& turn_id, const std::string& request_id,
                   rac_voice_agent_turn_event_callback_fn cb, void* user_data,
                   int32_t chunk_index = 0) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_TTS);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_TTS);
    auto* a = event.mutable_audio();
    if (data && size > 0)
        a->set_pcm(data, size);
    a->set_sample_rate_hz(sample_rate > 0 ? sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE);
    a->set_channels(1);
    a->set_encoding(runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE);
    a->set_is_final(is_final);
    a->set_chunk_index(chunk_index);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_error(rac_voice_agent_handle_t handle, rac_result_t code, const char* component_name,
                   const char* message, const std::string& session_id, const std::string& turn_id,
                   const std::string& request_id, rac_voice_agent_turn_event_callback_fn cb,
                   void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_ERROR);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* e = event.mutable_error();
    e->set_code(static_cast<int32_t>(code));
    e->set_message(message ? message : rac_error_message(code));
    e->set_component(component_name ? component_name : "voice_agent");
    e->set_is_recoverable(false);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

std::string d7_pick_turn_id(const std::string& request_id) {
    return request_id.empty() ? rac::voice_agent::detail::event_id("turn") : request_id;
}

constexpr size_t kMaxRememberedTurnCancellations = 64;

/// Registers one request id for the lifetime of a turn and exposes the
/// lock-independent cancellation latch to each blocking pipeline boundary.
/// The voice-agent operation mutex still serializes the actual pipeline; this
/// scope deliberately uses the separate cancellation mutex so `onCancel` can
/// interrupt an active LLM/TTS call instead of waiting for the turn to finish.
class D7TurnCancellationScope {
   public:
    D7TurnCancellationScope(rac_voice_agent_handle_t handle, std::string request_id)
        : handle_(handle), request_id_(std::move(request_id)) {}

    ~D7TurnCancellationScope() {
        auto& state = handle_->turn_cancellation;
        std::unique_lock<std::mutex> lock(state.mutex);
        state.interrupt_finished.wait(lock,
                                      [&] { return state.interrupt_request_id != request_id_; });
        if (state.active_request_id == request_id_) {
            state.active_request_id.clear();
            state.active_stage = rac_voice_agent_turn_stage::none;
            state.backend_started = false;
        }
        state.cancelled_request_ids.erase(request_id_);
        state.cancellation_order.erase(std::remove(state.cancellation_order.begin(),
                                                   state.cancellation_order.end(), request_id_),
                                       state.cancellation_order.end());
    }

    void activate() {
        auto& state = handle_->turn_cancellation;
        std::lock_guard<std::mutex> lock(state.mutex);
        state.active_request_id = request_id_;
        state.active_stage = rac_voice_agent_turn_stage::none;
        state.backend_started = false;
    }

    bool begin_stage(rac_voice_agent_turn_stage stage) {
        auto& state = handle_->turn_cancellation;
        std::lock_guard<std::mutex> lock(state.mutex);
        if (state.active_request_id != request_id_ ||
            state.cancelled_request_ids.contains(request_id_)) {
            return false;
        }
        state.active_stage = stage;
        state.backend_started = false;
        return true;
    }

    bool begin_backend() {
        auto& state = handle_->turn_cancellation;
        std::lock_guard<std::mutex> lock(state.mutex);
        if (state.active_request_id != request_id_ ||
            state.cancelled_request_ids.contains(request_id_)) {
            return false;
        }
        state.backend_started = true;
        return true;
    }

    void end_stage() {
        auto& state = handle_->turn_cancellation;
        std::unique_lock<std::mutex> lock(state.mutex);
        if (state.active_request_id == request_id_) {
            // Close backend admission before waiting for a dispatch that
            // already claimed this request. A cancellation arriving after the
            // callback returned must not target the next backend operation.
            state.backend_started = false;
            state.active_stage = rac_voice_agent_turn_stage::none;
        }
        state.interrupt_finished.wait(lock,
                                      [&] { return state.interrupt_request_id != request_id_; });
    }

    bool cancelled() const {
        auto& state = handle_->turn_cancellation;
        std::lock_guard<std::mutex> lock(state.mutex);
        return state.cancelled_request_ids.contains(request_id_);
    }

   private:
    rac_voice_agent_handle_t handle_;
    std::string request_id_;
};

void d7_request_cancellation(rac_voice_agent_handle_t handle, const std::string& request_id) {
    auto& state = handle->turn_cancellation;
    rac_voice_agent_turn_stage stage = rac_voice_agent_turn_stage::none;
    {
        std::lock_guard<std::mutex> lock(state.mutex);
        const bool first_request = state.cancelled_request_ids.insert(request_id).second;
        if (first_request) {
            state.cancellation_order.push_back(request_id);
        }
        while (state.cancellation_order.size() > kMaxRememberedTurnCancellations) {
            const std::string stale = std::move(state.cancellation_order.front());
            state.cancellation_order.pop_front();
            if (stale != state.active_request_id) {
                state.cancelled_request_ids.erase(stale);
            }
        }

        if (!first_request || state.active_request_id != request_id || !state.backend_started ||
            (state.active_stage != rac_voice_agent_turn_stage::llm &&
             state.active_stage != rac_voice_agent_turn_stage::tts)) {
            return;
        }
        stage = state.active_stage;
        state.interrupt_request_id = request_id;
    }

    // A backend cancel may need a mutex held by the active inference call
    // (MLX is one example), so never invoke it under the voice cancellation
    // mutex. end_stage() waits for this dispatch before the turn can advance,
    // preserving request/stage identity without a lock inversion.
    if (stage == rac_voice_agent_turn_stage::llm) {
        rac::llm::LifecycleLlmRef llm_ref{};
        if (rac::llm::acquire_lifecycle_llm(&llm_ref) == RAC_SUCCESS) {
            rac::llm::request_lifecycle_llm_cancel(&llm_ref);
            if (llm_ref.ops && llm_ref.ops->cancel) {
                (void)llm_ref.ops->cancel(llm_ref.impl);
            }
            rac::llm::release_lifecycle_llm(&llm_ref);
        } else if (handle->llm_handle) {
            (void)rac_llm_component_cancel(handle->llm_handle);
        }
    } else if (stage == rac_voice_agent_turn_stage::tts) {
        rac::lifecycle::LifecycleTtsRef tts_ref{};
        if (rac::lifecycle::acquire_lifecycle_tts(&tts_ref) == RAC_SUCCESS) {
            if (tts_ref.ops && tts_ref.ops->stop) {
                (void)tts_ref.ops->stop(tts_ref.impl);
            }
            rac::lifecycle::release_lifecycle_tts(&tts_ref);
        } else if (handle->tts_handle) {
            (void)rac_tts_component_stop(handle->tts_handle);
        }
    }

    {
        std::lock_guard<std::mutex> lock(state.mutex);
        if (state.interrupt_request_id == request_id) {
            state.interrupt_request_id.clear();
        }
    }
    state.interrupt_finished.notify_all();
}

void d7_emit_cancelled(rac_voice_agent_handle_t handle,
                       runanywhere::v1::PipelineState previous_state, const std::string& session_id,
                       const std::string& turn_id, const std::string& request_id,
                       rac_voice_agent_turn_event_callback_fn event_callback, void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* interrupted = event.mutable_interrupted();
    interrupted->set_reason(runanywhere::v1::INTERRUPT_REASON_APP_STOP);
    interrupted->set_detail("voice turn cancelled by the caller");
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, event_callback, user_data);

    d7_emit_state(handle, previous_state, runanywhere::v1::PIPELINE_STATE_STOPPED, session_id,
                  turn_id, request_id, event_callback, user_data);
    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_STOPPED,
                  runanywhere::v1::PIPELINE_STATE_IDLE, session_id, turn_id, request_id,
                  event_callback, user_data);
    rac::voice_agent::detail::emit_turn_lifecycle(
        handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_CANCELLED);
}

// ---------------------------------------------------------------------------
// Streaming LLM -> TTS bridge (hybrid voice: NPU LLM + CPU TTS).
//
// Instead of blocking for the whole answer and then synthesizing it in one shot,
// we consume the LLM token stream, cut it into speakable sentences with the shared
// chunk policy, synthesize each sentence, and emit it as its own AudioFrameEvent
// (is_final=false). Audio therefore starts after the FIRST sentence, and the app
// plays sentence N while commons generates+synthesizes N+1. When the LLM is on the
// NPU and TTS is on CPU (sherpa) the two never contend for the single Hexagon slot.
// ---------------------------------------------------------------------------

using rac::voice_agent::detail::cap_for_tts;
using rac::voice_agent::detail::drain_sentences;

struct D7StreamOutcome {
    rac_result_t status = RAC_SUCCESS;  // SUCCESS, CANCELLED, or a generation/synthesis error
    std::string full_text;              // raw LLM text (with <think>) for split_voice_response
    int32_t tokens = 0;
    std::vector<uint8_t> pcm;    // all synthesized float32-LE audio, concatenated (out_result WAV)
    int32_t sample_rate = 0;     // sample rate of the first synthesized chunk
    int32_t chunk_index = 0;     // running AudioFrameEvent index; == emitted count when done
    bool any_audio = false;
    bool playing_state_emitted = false;  // did we already move GENERATING_RESPONSE -> PLAYING_TTS
    double tts_ms = 0.0;                 // accumulated synthesis wall time
};

struct D7StreamState {
    rac_voice_agent_handle_t handle;
    bool have_lifecycle_tts;
    rac::lifecycle::LifecycleTtsRef* tts_ref;
    const std::string* session_id;
    const std::string* turn_id;
    const std::string* request_id;
    rac_voice_agent_turn_event_callback_fn cb;
    void* user_data;
    D7TurnCancellationScope* cancellation;
    std::string buf;  // token accumulation handed to drain_sentences
    D7StreamOutcome* out;
};

// Synthesize one already-sanitized sentence (hard-capped for the TTS phoneme
// limit) and emit each capped piece as an AudioFrameEvent. Returns non-SUCCESS to
// abort the turn (cancellation or a synthesis error).
rac_result_t d7_synth_and_emit(D7StreamState& st, const std::string& sentence) {
    for (const std::string& piece : cap_for_tts(sentence)) {
        if (piece.empty())
            continue;
        if (st.cancellation->cancelled())
            return RAC_ERROR_CANCELLED;

        rac_tts_result_t tts = {};
        rac_result_t rc;
        const auto t0 = std::chrono::steady_clock::now();
        if (st.have_lifecycle_tts) {
            rac_tts_service_t tts_service{st.tts_ref->ops, st.tts_ref->impl, st.tts_ref->model_id};
            rc = rac_tts_synthesize(&tts_service, piece.c_str(), nullptr, &tts);
        } else {
            rc = rac_tts_component_synthesize(st.handle->tts_handle, piece.c_str(), nullptr, &tts);
        }
        st.out->tts_ms +=
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        if (rc != RAC_SUCCESS) {
            rac_tts_result_free(&tts);
            return rc;
        }

        // First audio chunk moves the documented pipeline into PLAYING_TTS.
        if (!st.out->playing_state_emitted) {
            st.out->playing_state_emitted = true;
            d7_emit_state(st.handle, runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE,
                          runanywhere::v1::PIPELINE_STATE_PLAYING_TTS, *st.session_id, *st.turn_id,
                          *st.request_id, st.cb, st.user_data);
        }
        const int32_t sr = tts.sample_rate > 0 ? tts.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE;
        if (st.out->sample_rate == 0)
            st.out->sample_rate = sr;
        const bool has_pcm = tts.audio_data && tts.audio_size > 0;
        d7_emit_audio(st.handle, has_pcm ? tts.audio_data : nullptr, has_pcm ? tts.audio_size : 0,
                      sr, /*is_final=*/false, *st.session_id, *st.turn_id, *st.request_id, st.cb,
                      st.user_data, st.out->chunk_index++);
        if (has_pcm) {
            const uint8_t* b = static_cast<const uint8_t*>(tts.audio_data);
            st.out->pcm.insert(st.out->pcm.end(), b, b + tts.audio_size);
            st.out->any_audio = true;
        }
        rac_tts_result_free(&tts);
    }
    return RAC_SUCCESS;
}

// rac_llm_stream_callback_fn: fired per token on the calling thread. Accumulates
// text, drains any completed sentences, and synthesizes+emits them inline. Return
// RAC_FALSE to stop generation (cancellation or a fatal synthesis error).
rac_bool_t d7_on_llm_token(const char* token, void* user_data) {
    D7StreamState& st = *static_cast<D7StreamState*>(user_data);
    if (st.cancellation->cancelled()) {
        st.out->status = RAC_ERROR_CANCELLED;
        return RAC_FALSE;
    }
    if (token && token[0] != '\0') {
        st.out->full_text += token;
        st.buf += token;
        st.out->tokens += 1;
    }
    for (const std::string& sentence : drain_sentences(st.buf, /*flush=*/false)) {
        const rac_result_t rc = d7_synth_and_emit(st, sentence);
        if (rc != RAC_SUCCESS) {
            st.out->status = rc;
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

// Drive the whole LLM->TTS response. Lifecycle LLMs stream (NPU decode overlaps CPU
// synthesis); the legacy per-handle component path (no single-callback stream API)
// generates fully, then streams the TTS from the finished answer.
D7StreamOutcome d7_stream_response(rac_voice_agent_handle_t handle, bool have_lifecycle_llm,
                                   rac::llm::LifecycleLlmRef* llm_ref, bool have_lifecycle_tts,
                                   rac::lifecycle::LifecycleTtsRef* tts_ref, const char* prompt,
                                   const rac_llm_options_t* llm_opts, const std::string& session_id,
                                   const std::string& turn_id, const std::string& request_id,
                                   rac_voice_agent_turn_event_callback_fn cb, void* user_data,
                                   D7TurnCancellationScope& cancellation) {
    D7StreamOutcome out;
    D7StreamState st{handle,   have_lifecycle_tts, tts_ref, &session_id,   &turn_id,     &request_id,
                     cb,       user_data,          &cancellation,          std::string(), &out};

    if (have_lifecycle_llm && llm_ref->ops != nullptr && llm_ref->ops->generate_stream != nullptr) {
        rac_llm_service_t llm_service{llm_ref->ops, llm_ref->impl, llm_ref->model_id};
        const rac_result_t gen_rc =
            rac_llm_generate_stream(&llm_service, prompt, llm_opts, d7_on_llm_token, &st);
        if (out.status == RAC_SUCCESS && gen_rc != RAC_SUCCESS)
            out.status = gen_rc;
    } else if (have_lifecycle_llm && llm_ref->ops != nullptr && llm_ref->ops->generate != nullptr) {
        // Lifecycle LLM without a streaming op: generate the whole answer, then
        // chunk the finished text through TTS (same shape as the component path
        // below). Keeps non-streaming backends — and the unit-test mock — working
        // instead of failing the turn on a missing generate_stream.
        rac_llm_service_t llm_service{llm_ref->ops, llm_ref->impl, llm_ref->model_id};
        rac_llm_result_t llm = {};
        const rac_result_t gen_rc = rac_llm_generate(&llm_service, prompt, llm_opts, &llm);
        if (gen_rc != RAC_SUCCESS) {
            rac_llm_result_free(&llm);
            out.status = gen_rc;
            return out;
        }
        if (llm.text) {
            out.full_text = llm.text;
            st.buf = llm.text;
        }
        out.tokens = llm.completion_tokens;
        rac_llm_result_free(&llm);
    } else {
        rac_llm_result_t llm = {};
        const rac_result_t gen_rc =
            rac_llm_component_generate(handle->llm_handle, prompt, llm_opts, &llm);
        if (gen_rc != RAC_SUCCESS) {
            rac_llm_result_free(&llm);
            out.status = gen_rc;
            return out;
        }
        if (llm.text) {
            out.full_text = llm.text;
            st.buf = llm.text;
        }
        out.tokens = llm.completion_tokens;
        rac_llm_result_free(&llm);
    }
    if (out.status != RAC_SUCCESS)
        return out;

    // Flush the trailing partial (and, for the component path, the whole buffered
    // answer) through the chunker to TTS.
    for (const std::string& sentence : drain_sentences(st.buf, /*flush=*/true)) {
        const rac_result_t rc = d7_synth_and_emit(st, sentence);
        if (rc != RAC_SUCCESS) {
            out.status = rc;
            return out;
        }
    }
    return out;
}

// Whisper (and other STT engines) emit bracketed / parenthesized non-speech
// tags when handed silence or ambient noise — "[BLANK_AUDIO]", "[wind blowing]",
// "(music)", "[ Silence ]", "<no speech>", "♪♪♪", "...", etc. In an always-on
// listening session the mic keeps capping ~15 s buffers of near-silence between
// the user's real utterances; if such a phantom transcript is treated as user
// speech, the agent answers its own ambient noise and loops forever. Treat a
// transcript that reduces to nothing but bracketed tags, punctuation, or symbols
// as empty so the turn is skipped. Real speech always leaves alphanumeric
// characters OUTSIDE brackets, so this never drops a genuine utterance.
bool transcript_is_non_speech(const char* text) {
    if (text == nullptr) {
        return true;
    }
    int depth = 0;
    for (const char* p = text; *p != '\0'; ++p) {
        const unsigned char c = static_cast<unsigned char>(*p);
        if (c == '[' || c == '(' || c == '{' || c == '<') {
            ++depth;
            continue;
        }
        if (c == ']' || c == ')' || c == '}' || c == '>') {
            if (depth > 0) {
                --depth;
            }
            continue;
        }
        if (depth > 0) {
            continue;  // inside a non-speech tag
        }
        // Content = ASCII alphanumeric OR any non-ASCII byte (>= 0x80). The latter
        // covers every UTF-8 multibyte codepoint, so non-Latin scripts (Chinese,
        // Arabic, Japanese, …) count as real speech rather than being byte-wise
        // misclassified as non-speech and dropped. Matches Kotlin's Unicode-aware
        // Char.isLetterOrDigit() closely enough for this gate's purpose.
        if (std::isalnum(c) != 0 || c >= 0x80) {
            return false;  // real content outside any tag → genuine speech
        }
    }
    return true;
}

}  // namespace

namespace rac::voice_agent::detail {

rac_result_t d7_process_utterance(rac_voice_agent_handle_t handle, const std::string& audio,
                                  const std::string& session_id, const std::string& turn_id,
                                  const std::string& request_id, const std::string& language_code,
                                  rac_voice_agent_turn_event_callback_fn event_callback,
                                  void* user_data, runanywhere::v1::VoiceAgentResult* out_result) {
    if (audio.empty()) {
        d7_emit_error(handle, RAC_ERROR_INVALID_ARGUMENT, "voice_agent",
                      "voice turn buffer is empty", session_id, turn_id, request_id, event_callback,
                      user_data);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // The request id is the cancellation key. Older callers may omit it, in
    // which case the already-unique generated turn id is the safe fallback.
    const std::string cancellation_id = request_id.empty() ? turn_id : request_id;
    D7TurnCancellationScope cancellation(handle, cancellation_id);
    if (cancellation.cancelled()) {
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_IDLE, session_id, turn_id,
                          request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }

    runanywhere::v1::VoiceAgentComponentStates component_states;
    fill_component_states(handle, &component_states);
    const struct {
        runanywhere::v1::ComponentLifecycleState state;
        const char* name;
        const char* message;
    } required[] = {
        {.state = component_states.stt_state(),
         .name = "stt",
         .message = "STT component is not loaded"},
        {.state = component_states.llm_state(),
         .name = "llm",
         .message = "LLM component is not loaded"},
        {.state = component_states.tts_state(),
         .name = "tts",
         .message = "TTS component is not loaded"},
        {.state = component_states.vad_state(),
         .name = "vad",
         .message = "VAD component is not initialized"},
    };
    for (const auto& entry : required) {
        if (entry.state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            d7_emit_error(handle, RAC_ERROR_NOT_INITIALIZED, entry.name, entry.message, session_id,
                          turn_id, request_id, event_callback, user_data);
            emit_component_failure(handle, entry.name, RAC_ERROR_NOT_INITIALIZED, entry.message);
            return RAC_ERROR_NOT_INITIALIZED;
        }
    }

    // Per-turn telemetry: publish a MetricsEvent on every exit (success or any
    // failure) so the turn lands under the "voice" modality. This path uses
    // early `return rc` at each stage, so an RAII guard is the clean way to
    // cover all exits. Declared BEFORE the lock so it destructs (and publishes)
    // AFTER the handle mutex is released. `armed` gates it to turns that
    // actually started (not the pre-flight config rejections above).
    struct TurnMetricsGuard {
        std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
        double stt_ms = 0.0;
        double llm_ms = 0.0;
        double tts_ms = 0.0;
        int64_t tokens = 0;
        std::string session_id;
        std::string model_id;
        std::string framework;
        int32_t transcript_chars = 0;
        int32_t response_chars = 0;
        int32_t turn_index = 0;
        bool armed = false;
        rac_result_t error_code = RAC_SUCCESS;
        std::string error_message;
        ~TurnMetricsGuard() {
            if (!armed)
                return;
            const double e2e_ms =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
                    .count();
            rac::voice_agent::detail::publish_voice_turn_metrics(
                stt_ms, llm_ms, tts_ms, e2e_ms, tokens,
                session_id.empty() ? nullptr : session_id.c_str(),
                model_id.empty() ? nullptr : model_id.c_str(),
                framework.empty() ? nullptr : framework.c_str(), transcript_chars, response_chars,
                turn_index, error_code == RAC_ERROR_CANCELLED ? RAC_TRUE : RAC_FALSE, error_code,
                error_message.empty() ? nullptr : error_message.c_str());
        }
    } turn_metrics;
    turn_metrics.session_id = session_id;
    turn_metrics.turn_index = handle->turn_counter.fetch_add(1, std::memory_order_relaxed);

    std::lock_guard<std::mutex> lock(handle->mutex);

    cancellation.activate();
    if (cancellation.cancelled()) {
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_IDLE, session_id, turn_id,
                          request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }

    emit_component_states(handle);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_STARTED);
    turn_metrics.armed = true;
    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_IDLE,
                  runanywhere::v1::PIPELINE_STATE_LISTENING, session_id, turn_id, request_id,
                  event_callback, user_data);

    // Surface a real VAD verdict for the turn instead of
    // emitting a hard-coded SPEECH_STARTED/SPEECH_ENDED pair around STT.
    // The per-turn d7 path receives a pre-framed audio buffer, so we run
    // the VAD component once over the whole buffer and emit a single
    // SPEECH_ACTIVITY event reflecting the real verdict. Frontends that
    // need per-frame VAD edges should use the streaming pipeline (which
    // runs VADGateNode per frame); the d7 turn ABI only owes them an
    // honest "did this turn contain speech?" signal.
    auto run_turn_vad = [&]() -> bool {
        const size_t bytes = audio.size();
        if (bytes < sizeof(int16_t) || (bytes % sizeof(int16_t)) != 0)
            return false;
        const int16_t* pcm = reinterpret_cast<const int16_t*>(audio.data());
        const size_t count = bytes / sizeof(int16_t);
        std::vector<float> floats(count);
        constexpr float kInv = 1.0f / 32768.0f;
        for (size_t i = 0; i < count; ++i) {
            floats[i] = static_cast<float>(pcm[i]) * kInv;
        }
        rac::lifecycle::LifecycleVadRef vad_ref{};
        const bool have_lifecycle_vad =
            rac::lifecycle::acquire_lifecycle_vad(&vad_ref) == RAC_SUCCESS;
        rac_bool_t is_speech = RAC_FALSE;
        if (have_lifecycle_vad && vad_ref.ops && vad_ref.ops->process) {
            (void)vad_ref.ops->process(vad_ref.impl, floats.data(), count, &is_speech);
            rac::lifecycle::release_lifecycle_vad(&vad_ref);
        } else if (handle->vad_handle) {
            (void)rac_vad_component_process(handle->vad_handle, floats.data(), count, &is_speech);
        }
        return is_speech == RAC_TRUE;
    };
    if (!cancellation.begin_stage(rac_voice_agent_turn_stage::vad)) {
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_LISTENING, session_id, turn_id,
                          request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }
    const bool turn_has_speech = run_turn_vad();
    cancellation.end_stage();
    if (cancellation.cancelled()) {
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_LISTENING, session_id, turn_id,
                          request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }
    if (turn_has_speech) {
        d7_emit_vad(handle, runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                    /*is_speech=*/true, session_id, turn_id, request_id, event_callback, user_data);
    }

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_LISTENING,
                  runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH, session_id, turn_id,
                  request_id, event_callback, user_data);

    // Dispatch through lifecycle refs when the
    // canonical lifecycle bridge owns the loaded models; fall back to the
    // voice-agent's per-handle component for legacy load paths.
    rac::lifecycle::LifecycleSttRef stt_ref{};
    const bool have_lifecycle_stt = rac::lifecycle::acquire_lifecycle_stt(&stt_ref) == RAC_SUCCESS;

    rac_stt_result_t stt = {};
    rac_result_t rc;
    const auto t_stt = std::chrono::steady_clock::now();
    if (!cancellation.begin_stage(rac_voice_agent_turn_stage::stt)) {
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH, session_id,
                          turn_id, request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }
    if (have_lifecycle_stt) {
        rac_stt_service_t stt_service{stt_ref.ops, stt_ref.impl, stt_ref.model_id};
        rc = rac_stt_transcribe(&stt_service, audio.data(), audio.size(), nullptr, &stt);
    } else {
        rc = rac_stt_component_transcribe(handle->stt_handle, audio.data(), audio.size(), nullptr,
                                          &stt);
    }
    cancellation.end_stage();
    turn_metrics.stt_ms =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_stt).count();
    if (cancellation.cancelled()) {
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH, session_id,
                          turn_id, request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        turn_metrics.error_code = rc;
        turn_metrics.error_message = "STT transcription failed";
        d7_emit_error(handle, rc, "stt", "STT transcription failed", session_id, turn_id,
                      request_id, event_callback, user_data);
        emit_component_failure(handle, "stt", rc, "STT transcription failed");
        return rc;
    }
    if (!stt.text || stt.text[0] == '\0') {
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        turn_metrics.error_code = RAC_ERROR_INVALID_STATE;
        turn_metrics.error_message = "STT transcription was empty";
        d7_emit_error(handle, RAC_ERROR_INVALID_STATE, "stt", "STT transcription was empty",
                      session_id, turn_id, request_id, event_callback, user_data);
        emit_component_failure(handle, "stt", RAC_ERROR_INVALID_STATE,
                               "STT transcription was empty");
        return RAC_ERROR_INVALID_STATE;
    }
    if (transcript_is_non_speech(stt.text)) {
        // STT hallucinated a non-speech tag (e.g. "[BLANK_AUDIO]", "[wind
        // blowing]") on a silence/noise buffer. Skip the turn QUIETLY — no LLM,
        // no TTS, and NO error event — and drop back to listening, so an
        // always-on session does not answer its own ambient noise in a loop.
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        if (turn_has_speech) {
            d7_emit_vad(handle, runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                        /*is_speech=*/false, session_id, turn_id, request_id, event_callback,
                        user_data);
        }
        d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH,
                      runanywhere::v1::PIPELINE_STATE_IDLE, session_id, turn_id, request_id,
                      event_callback, user_data);
        return RAC_SUCCESS;
    }
    // Only emit the matching "speech ended" event if we
    // previously emitted "speech started" for this turn. Emitting
    // SPEECH_ENDED unconditionally would still desynchronize frontends
    // tracking VAD state when the turn contained no detected speech.
    if (turn_has_speech) {
        d7_emit_vad(handle, runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                    /*is_speech=*/false, session_id, turn_id, request_id, event_callback,
                    user_data);
    }
    turn_metrics.transcript_chars = stt.text ? static_cast<int32_t>(std::strlen(stt.text)) : 0;
    d7_emit_user_said(handle, stt.text, language_code, session_id, turn_id, request_id,
                      event_callback, user_data);

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH,
                  runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE, session_id, turn_id,
                  request_id, event_callback, user_data);

    rac::llm::LifecycleLlmRef llm_ref{};
    const bool have_lifecycle_llm = rac::llm::acquire_lifecycle_llm(&llm_ref) == RAC_SUCCESS;
    if (have_lifecycle_llm) {
        if (llm_ref.model_id != nullptr)
            turn_metrics.model_id = llm_ref.model_id;
        if (llm_ref.framework_name != nullptr)
            turn_metrics.framework = llm_ref.framework_name;
    }
    // Build a proper voice-assistant turn: a spoken-style system prompt, a
    // brevity cap, and the prior conversation so replies stay short, on-topic,
    // and context-aware — instead of feeding the raw transcript with no guidance
    // (which is why responses were rambly/useless).
    std::vector<const char*> history_ptrs;
    history_ptrs.reserve(handle->conversation_history.size() * 2);
    for (const auto& turn : handle->conversation_history) {
        if (turn.user_text.empty()) {
            continue;
        }
        history_ptrs.push_back(turn.user_text.c_str());
        history_ptrs.push_back(turn.assistant_text.c_str());
    }
    rac_llm_options_t llm_opts = make_voice_llm_options();
    if (!history_ptrs.empty()) {
        llm_opts.history = history_ptrs.data();
        llm_opts.n_history = static_cast<int32_t>(history_ptrs.size());
    }

    if (have_lifecycle_llm) {
        // Every turn owns a fresh cancellation scope. Clear only the
        // lifecycle bookkeeping bit here; each backend resets its own
        // request-scoped cancel state when generation begins.
        rac::llm::clear_lifecycle_llm_cancel(&llm_ref);
    }

    // Acquire the TTS voice BEFORE generation: the streaming path synthesizes and
    // emits audio from INSIDE the LLM token stream, so the voice must be resident
    // when the first sentence lands. In the hybrid deployment the LLM is QHexRT
    // (NPU) and STT/TTS are sherpa (CPU), so they never contend for the single
    // Hexagon slot and CPU synthesis overlaps NPU decode.
    rac::lifecycle::LifecycleTtsRef tts_ref{};
    const bool have_lifecycle_tts = rac::lifecycle::acquire_lifecycle_tts(&tts_ref) == RAC_SUCCESS;

    auto release_pipeline = [&]() {
        if (have_lifecycle_tts) {
            rac::lifecycle::release_lifecycle_tts(&tts_ref);
        }
        if (have_lifecycle_llm) {
            rac::llm::release_lifecycle_llm(&llm_ref);
        }
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
    };

    // LLM generation and streaming TTS run under one cancellation stage: barge-in
    // cancels the LLM (halting generation), and the token callback then stops
    // enqueuing further speech.
    if (!cancellation.begin_stage(rac_voice_agent_turn_stage::llm) ||
        !cancellation.begin_backend()) {
        rac_stt_result_free(&stt);
        release_pipeline();
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle, runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE, session_id,
                          turn_id, request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }

    const auto t_response = std::chrono::steady_clock::now();
    D7StreamOutcome stream =
        d7_stream_response(handle, have_lifecycle_llm, &llm_ref, have_lifecycle_tts, &tts_ref,
                           stt.text, &llm_opts, session_id, turn_id, request_id, event_callback,
                           user_data, cancellation);
    cancellation.end_stage();
    const double response_ms =
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_response)
            .count();
    turn_metrics.tts_ms = stream.tts_ms;
    // Streaming interleaves decode and synthesis; attribute the non-synthesis wall
    // time to the LLM as an approximation.
    turn_metrics.llm_ms = response_ms > stream.tts_ms ? response_ms - stream.tts_ms : 0.0;
    turn_metrics.tokens = stream.tokens;

    if (cancellation.cancelled() || stream.status == RAC_ERROR_CANCELLED) {
        rac_stt_result_free(&stt);
        release_pipeline();
        turn_metrics.error_code = RAC_ERROR_CANCELLED;
        turn_metrics.error_message = "Voice turn cancelled";
        d7_emit_cancelled(handle,
                          stream.playing_state_emitted
                              ? runanywhere::v1::PIPELINE_STATE_PLAYING_TTS
                              : runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE,
                          session_id, turn_id, request_id, event_callback, user_data);
        return RAC_ERROR_CANCELLED;
    }
    if (stream.status != RAC_SUCCESS) {
        // A synthesis error surfaces once audio has begun (tts); anything earlier
        // is a generation failure (llm).
        const char* failed = stream.any_audio ? "tts" : "llm";
        rac_stt_result_free(&stt);
        release_pipeline();
        turn_metrics.error_code = stream.status;
        turn_metrics.error_message = "Voice response streaming failed";
        d7_emit_error(handle, stream.status, failed, "Voice response streaming failed", session_id,
                      turn_id, request_id, event_callback, user_data);
        emit_component_failure(handle, failed, stream.status, "Voice response streaming failed");
        return stream.status;
    }

    const VoiceResponseParts response = split_voice_response(stream.full_text.c_str());
    turn_metrics.response_chars = static_cast<int32_t>(response.answer.size());
    const rac_result_t response_status = validate_voice_response(response);
    if (response_status != RAC_SUCCESS) {
        rac_stt_result_free(&stt);
        release_pipeline();
        turn_metrics.error_code = response_status;
        turn_metrics.error_message = kVoiceAgentEmptyResponseMessage;
        d7_emit_error(handle, response_status, "llm", kVoiceAgentEmptyResponseMessage, session_id,
                      turn_id, request_id, event_callback, user_data);
        emit_component_failure(handle, "llm", response_status, kVoiceAgentEmptyResponseMessage);
        return response_status;
    }

    // Remember this turn so the next one has context. The typed turn is
    // flattened into rac_llm_options_t.history as alternating user,assistant.
    // Bound to the same flattened-entry budget so the prompt stays within the
    // context window.
    if (stt.text != nullptr && stt.text[0] != '\0') {
        handle->conversation_history.push_back(
            VoiceConversationTurn{.user_text = stt.text, .assistant_text = response.answer});
        const size_t max_turns = kVoiceAgentMaxHistoryEntries / 2;
        if (handle->conversation_history.size() > max_turns) {
            const size_t excess = handle->conversation_history.size() - max_turns;
            handle->conversation_history.erase(handle->conversation_history.begin(),
                                               handle->conversation_history.begin() +
                                                   static_cast<std::ptrdiff_t>(excess));
        }
    }

    // Emit the full assistant text (thinking + answer) for text-facing subscribers;
    // the spoken audio has already streamed out sentence-by-sentence above.
    if (!response.thinking.empty()) {
        d7_emit_assistant_token(handle, response.thinking.c_str(), false,
                                runanywhere::v1::TOKEN_KIND_THOUGHT, session_id, turn_id,
                                request_id, event_callback, user_data);
    }
    d7_emit_assistant_token(handle, response.answer.c_str(), true,
                            runanywhere::v1::TOKEN_KIND_ANSWER, session_id, turn_id, request_id,
                            event_callback, user_data);

    // If no speakable audio streamed (an empty/degenerate answer), still move
    // through PLAYING_TTS so the documented state machine stays valid.
    if (!stream.playing_state_emitted) {
        d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE,
                      runanywhere::v1::PIPELINE_STATE_PLAYING_TTS, session_id, turn_id, request_id,
                      event_callback, user_data);
    }
    // Terminal audio frame: is_final=true marks end-of-stream for consumers (the
    // spoken chunks above were all emitted with is_final=false).
    d7_emit_audio(handle, nullptr, 0,
                  stream.sample_rate > 0 ? stream.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE, true,
                  session_id, turn_id, request_id, event_callback, user_data, stream.chunk_index);

    // When the caller wants the synthesized reply inline (the feed-audio ingress
    // path), package transcript + response + the full reply as a self-describing
    // WAV (every streamed chunk concatenated) so the SDK plays it directly.
    if (out_result) {
        out_result->set_speech_detected(turn_has_speech);
        out_result->set_transcription(stt.text);
        if (!response.answer.empty()) {
            out_result->set_assistant_response(response.answer);
        }
        if (!response.thinking.empty()) {
            out_result->set_thinking_content(response.thinking);
        }
        if (!stream.pcm.empty()) {
            void* wav_data = nullptr;
            size_t wav_size = 0;
            if (rac_audio_float32_to_wav(stream.pcm.data(), stream.pcm.size(),
                                         stream.sample_rate > 0 ? stream.sample_rate
                                                                : RAC_TTS_DEFAULT_SAMPLE_RATE,
                                         &wav_data, &wav_size) == RAC_SUCCESS &&
                wav_data && wav_size > 0) {
                out_result->set_synthesized_audio(wav_data, wav_size);
                std::free(wav_data);
            }
        }
        fill_component_states(handle, out_result->mutable_final_state());
    }

    // Honor the documented PLAYING_TTS -> COOLDOWN -> IDLE
    // pathway so frontends gating the microphone on
    // rac_audio_pipeline_can_activate_microphone() get the 800ms feedback-
    // prevention window the architecture promises. Skipping COOLDOWN here
    // let the mic reopen instantly after TTS, capturing TTS bleed-through.
    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_PLAYING_TTS,
                  runanywhere::v1::PIPELINE_STATE_COOLDOWN, session_id, turn_id, request_id,
                  event_callback, user_data);
    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_COOLDOWN,
                  runanywhere::v1::PIPELINE_STATE_IDLE, session_id, turn_id, request_id,
                  event_callback, user_data);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_COMPLETED, stt.text,
                        response.answer.c_str());

    rac_stt_result_free(&stt);
    release_pipeline();
    return RAC_SUCCESS;
}

}  // namespace rac::voice_agent::detail

#endif  // RAC_HAVE_PROTOBUF

extern "C" rac_result_t rac_voice_agent_process_turn_proto(
    rac_voice_agent_handle_t handle, const uint8_t* request_bytes, size_t request_size,
    rac_voice_agent_turn_event_callback_fn event_callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)request_bytes;
    (void)request_size;
    (void)event_callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    using namespace rac::voice_agent::detail;
    if (!handle || !event_callback)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!proto_bytes_valid(request_bytes, request_size))
        return RAC_ERROR_DECODING_ERROR;

    runanywhere::v1::VoiceAgentTurnRequest request;
    if (!request.ParseFromArray(proto_parse_data(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const std::string session_id = request.session_id();
    const std::string request_id = request.request_id();
    const std::string turn_id = d7_pick_turn_id(request_id);

    // Admit under the in-flight barrier so rac_voice_agent_destroy's
    // drain loop covers this full STT+LLM+TTS turn. The d7 path reads
    // is_configured below outside handle->mutex, so without the barrier a
    // concurrent destroy could flip is_shutting_down after that read and tear
    // the agent down mid-turn while this thread still emits events on it.
    InFlightGuard guard(handle);
    if (!guard.admitted()) {
        d7_emit_error(handle, RAC_ERROR_INVALID_STATE, "voice_agent",
                      "voice agent is shutting down", session_id, turn_id, request_id,
                      event_callback, user_data);
        return RAC_ERROR_INVALID_STATE;
    }

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        d7_emit_error(handle, RAC_ERROR_NOT_INITIALIZED, "voice_agent",
                      "voice agent is not initialized", session_id, turn_id, request_id,
                      event_callback, user_data);
        emit_component_failure(handle, "voice_agent", RAC_ERROR_NOT_INITIALIZED,
                               "voice agent is not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // The VAD -> STT -> LLM -> TTS pipeline + event emission is shared with
    // the streaming feed-audio ingress path (rac_voice_agent_feed_audio_proto).
    const std::string language_code = request.session_config().has_language_code()
                                          ? request.session_config().language_code()
                                          : std::string();
    return rac::voice_agent::detail::d7_process_utterance(
        handle, request.audio_data(), session_id, turn_id, request_id, language_code,
        event_callback, user_data, /*out_result=*/nullptr);
#endif
}

extern "C" rac_result_t rac_voice_agent_cancel_turn_proto(rac_voice_agent_handle_t handle,
                                                          const uint8_t* request_bytes,
                                                          size_t request_size) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)request_bytes;
    (void)request_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    using namespace rac::voice_agent::detail;
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!proto_bytes_valid(request_bytes, request_size))
        return RAC_ERROR_DECODING_ERROR;

    runanywhere::v1::VoiceAgentTurnRequest request;
    if (!request.ParseFromArray(proto_parse_data(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.request_id().empty())
        return RAC_ERROR_INVALID_ARGUMENT;

    InFlightGuard guard(handle);
    if (!guard.admitted())
        return RAC_ERROR_INVALID_STATE;

    // Latch the exact request before forwarding to a backend. If the worker
    // isolate has not entered the turn yet, d7_process_utterance observes this
    // id at its first boundary and exits without starting inference. If it is
    // already running, only the matching turn's active modality is interrupted.
    d7_request_cancellation(handle, request.request_id());

    RAC_LOG_INFO("VoiceAgent", "Cancellation requested for voice turn %s",
                 request.request_id().c_str());
    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_voice_agent_transcribe_proto(rac_voice_agent_handle_t handle,
                                                         const uint8_t* request_bytes,
                                                         size_t request_size,
                                                         rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)request_bytes;
    (void)request_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    using namespace rac::voice_agent::detail;
    if (!handle) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    if (!proto_bytes_valid(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "transcribe request bytes are invalid");
    }
    runanywhere::v1::VoiceAgentTranscribeProtoRequest request;
    if (!request.ParseFromArray(proto_parse_data(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VoiceAgentTranscribeProtoRequest");
    }
    const std::string& audio = request.audio_data();
    if (audio.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "transcribe request is missing audio_data");
    }

    // Admit under the in-flight barrier so destroy()'s drain loop
    // covers this STT inference call (which takes no handle->mutex at all).
    InFlightGuard guard(handle);
    if (!guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "voice agent is shutting down");
    }

    // Prefer the canonical lifecycle STT ref; fall back
    // to the component-handle path so legacy callers still work end-to-end.
    rac::lifecycle::LifecycleSttRef stt_ref{};
    const bool have_lifecycle_stt = rac::lifecycle::acquire_lifecycle_stt(&stt_ref) == RAC_SUCCESS;
    if (!have_lifecycle_stt &&
        (!handle->stt_handle ||
         rac_stt_component_get_state(handle->stt_handle) != RAC_LIFECYCLE_STATE_LOADED)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "STT component is not loaded");
    }

    rac_stt_result_t stt = {};
    rac_result_t rc;
    if (have_lifecycle_stt) {
        rac_stt_service_t stt_service{stt_ref.ops, stt_ref.impl, stt_ref.model_id};
        rc = rac_stt_transcribe(&stt_service, audio.data(), audio.size(), nullptr, &stt);
    } else {
        rc = rac_stt_component_transcribe(handle->stt_handle, audio.data(), audio.size(), nullptr,
                                          &stt);
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        return rac_proto_buffer_set_error(out_result, rc, "STT transcription failed");
    }
    runanywhere::v1::STTOutput output;
    if (stt.text)
        output.set_text(stt.text);
    output.set_confidence(stt.confidence);
    if (stt.detected_language)
        output.set_language_code(stt.detected_language);
    if (stt.processing_time_ms > 0) {
        auto* metadata = output.mutable_metadata();
        metadata->set_processing_time_ms(stt.processing_time_ms);
    }
    output.set_timestamp_ms(rac_get_current_time_ms());
    rac_stt_result_free(&stt);
    if (have_lifecycle_stt) {
        rac::lifecycle::release_lifecycle_stt(&stt_ref);
    }
    return copy_proto_message(output, out_result);
#endif
}

extern "C" rac_result_t rac_voice_agent_synthesize_speech_proto(rac_voice_agent_handle_t handle,
                                                                const uint8_t* request_bytes,
                                                                size_t request_size,
                                                                rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)request_bytes;
    (void)request_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    using namespace rac::voice_agent::detail;
    if (!handle) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    if (!proto_bytes_valid(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "synthesize request bytes are invalid");
    }
    runanywhere::v1::VoiceAgentSynthesizeSpeechProtoRequest request;
    if (!request.ParseFromArray(proto_parse_data(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VoiceAgentSynthesizeSpeechProtoRequest");
    }
    if (request.text().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "synthesize request is missing text");
    }

    // Admit under the in-flight barrier so destroy()'s drain loop
    // covers this TTS synthesis call (which takes no handle->mutex at all).
    InFlightGuard guard(handle);
    if (!guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "voice agent is shutting down");
    }

    // Prefer the canonical lifecycle TTS ref; fall back
    // to the component-handle path so legacy callers still work end-to-end.
    rac::lifecycle::LifecycleTtsRef tts_ref{};
    const bool have_lifecycle_tts = rac::lifecycle::acquire_lifecycle_tts(&tts_ref) == RAC_SUCCESS;
    if (!have_lifecycle_tts &&
        (!handle->tts_handle ||
         rac_tts_component_get_state(handle->tts_handle) != RAC_LIFECYCLE_STATE_LOADED)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "TTS component is not loaded");
    }

    rac_tts_result_t tts = {};
    rac_result_t rc;
    if (have_lifecycle_tts) {
        rac_tts_service_t tts_service{tts_ref.ops, tts_ref.impl, tts_ref.model_id};
        rc = rac_tts_synthesize(&tts_service, request.text().c_str(), nullptr, &tts);
    } else {
        rc =
            rac_tts_component_synthesize(handle->tts_handle, request.text().c_str(), nullptr, &tts);
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_tts) {
            rac::lifecycle::release_lifecycle_tts(&tts_ref);
        }
        return rac_proto_buffer_set_error(out_result, rc, "TTS synthesis failed");
    }
    runanywhere::v1::TTSOutput output;
    if (tts.audio_data && tts.audio_size > 0)
        output.set_audio_data(tts.audio_data, tts.audio_size);
    output.set_sample_rate(tts.sample_rate > 0 ? tts.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE);
    output.set_duration_ms(tts.duration_ms);
    output.set_timestamp_ms(rac_get_current_time_ms());
    output.set_is_final(true);
    output.set_audio_size_bytes(static_cast<int64_t>(tts.audio_size));
    rac_tts_result_free(&tts);
    if (have_lifecycle_tts) {
        rac::lifecycle::release_lifecycle_tts(&tts_ref);
    }
    return copy_proto_message(output, out_result);
#endif
}

extern "C" rac_result_t
rac_voice_agent_component_create_proto(const uint8_t* config_bytes, size_t config_size,
                                       rac_voice_agent_handle_t* out_handle) {
    if (!out_handle)
        return RAC_ERROR_INVALID_ARGUMENT;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)config_bytes;
    (void)config_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    using namespace rac::voice_agent::detail;
    if (!proto_bytes_valid(config_bytes, config_size))
        return RAC_ERROR_DECODING_ERROR;
    runanywhere::v1::VoiceAgentComposeConfig proto;
    if (config_size > 0 && !proto.ParseFromArray(proto_parse_data(config_bytes, config_size),
                                                 static_cast<int>(config_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    rac_voice_agent_handle_t handle = nullptr;
    rac_result_t rc = rac_voice_agent_create_standalone(&handle);
    if (rc != RAC_SUCCESS)
        return rc;
    if (config_size > 0) {
        rac_voice_agent_config_t config = config_from_proto(proto);
        rc = rac_voice_agent_initialize(handle, &config);
        if (rc != RAC_SUCCESS) {
            rac_voice_agent_destroy(handle);
            return rc;
        }
    }
    *out_handle = handle;
    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_voice_agent_component_destroy_proto(rac_voice_agent_handle_t handle) {
    if (handle)
        rac_voice_agent_destroy(handle);
    return RAC_SUCCESS;
}
