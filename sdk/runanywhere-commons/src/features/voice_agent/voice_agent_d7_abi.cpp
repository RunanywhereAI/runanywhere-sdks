/**
 * @file voice_agent_d7_abi.cpp
 * @brief Full-session voice-agent C ABI — proto-byte streaming
 *        path used by SDK frontends to drive a complete voice turn with
 *        session/turn/request correlation.
 *
 * Hosts the SDK-facing surface:
 *   - `rac_voice_agent_process_turn_proto`,
 *   - `rac_voice_agent_transcribe_proto`,
 *   - `rac_voice_agent_synthesize_speech_proto`,
 *   - `rac_voice_agent_component_create_proto`,
 *   - `rac_voice_agent_component_destroy_proto`,
 *   - and the d7_emit_* helpers used to fan a `VoiceEvent` out to (a) the
 *     per-call turn-event callback, (b) the per-handle proto callback
 *     registered via `rac_voice_agent_set_proto_callback`, and (c) the
 *     global SDKEvent publisher.
 */

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
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
        RAC_LOG_WARNING(
            "VoiceAgent",
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
                             const std::string& session_id, const std::string& turn_id,
                             const std::string& request_id,
                             rac_voice_agent_turn_event_callback_fn cb, void* user_data) {
    runanywhere::v1::VoiceEvent event;
    event.set_category(runanywhere::v1::EVENT_CATEGORY_LLM);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_LLM);
    auto* t = event.mutable_assistant_token();
    if (text)
        t->set_text(text);
    t->set_is_final(is_final);
    t->set_kind(runanywhere::v1::TOKEN_KIND_ANSWER);
    d7_emit_voice_event(handle, &event, session_id, turn_id, request_id, cb, user_data);
}

void d7_emit_audio(rac_voice_agent_handle_t handle, const void* data, size_t size,
                   int32_t sample_rate, bool is_final, const std::string& session_id,
                   const std::string& turn_id, const std::string& request_id,
                   rac_voice_agent_turn_event_callback_fn cb, void* user_data) {
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

}  // namespace

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

    const std::string& audio = request.audio_data();
    if (audio.empty()) {
        d7_emit_error(handle, RAC_ERROR_INVALID_ARGUMENT, "voice_agent",
                      "voice turn request is missing audio_data", session_id, turn_id, request_id,
                      event_callback, user_data);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    emit_component_states(handle);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_STARTED);
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
    const bool turn_has_speech = run_turn_vad();
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
        d7_emit_error(handle, RAC_ERROR_INVALID_STATE, "stt", "STT transcription was empty",
                      session_id, turn_id, request_id, event_callback, user_data);
        emit_component_failure(handle, "stt", RAC_ERROR_INVALID_STATE,
                               "STT transcription was empty");
        return RAC_ERROR_INVALID_STATE;
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
    d7_emit_user_said(handle, stt.text,
                      request.session_config().has_language_code()
                          ? request.session_config().language_code()
                          : std::string(),
                      session_id, turn_id, request_id, event_callback, user_data);

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH,
                  runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE, session_id, turn_id,
                  request_id, event_callback, user_data);

    rac::llm::LifecycleLlmRef llm_ref{};
    const bool have_lifecycle_llm = rac::llm::acquire_lifecycle_llm(&llm_ref) == RAC_SUCCESS;
    rac_llm_result_t llm = {};
    if (have_lifecycle_llm) {
        rac_llm_service_t llm_service{llm_ref.ops, llm_ref.impl, llm_ref.model_id};
        rc = rac_llm_generate(&llm_service, stt.text, nullptr, &llm);
    } else {
        rc = rac_llm_component_generate(handle->llm_handle, stt.text, nullptr, &llm);
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_llm) {
            rac::llm::release_lifecycle_llm(&llm_ref);
        }
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        d7_emit_error(handle, rc, "llm", "LLM generation failed", session_id, turn_id, request_id,
                      event_callback, user_data);
        emit_component_failure(handle, "llm", rc, "LLM generation failed");
        return rc;
    }
    d7_emit_assistant_token(handle, llm.text, true, session_id, turn_id, request_id, event_callback,
                            user_data);

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_GENERATING_RESPONSE,
                  runanywhere::v1::PIPELINE_STATE_PLAYING_TTS, session_id, turn_id, request_id,
                  event_callback, user_data);

    rac::lifecycle::LifecycleTtsRef tts_ref{};
    const bool have_lifecycle_tts = rac::lifecycle::acquire_lifecycle_tts(&tts_ref) == RAC_SUCCESS;
    rac_tts_result_t tts = {};
    if (have_lifecycle_tts) {
        rac_tts_service_t tts_service{tts_ref.ops, tts_ref.impl, tts_ref.model_id};
        rc = rac_tts_synthesize(&tts_service, llm.text, nullptr, &tts);
    } else {
        rc = rac_tts_component_synthesize(handle->tts_handle, llm.text, nullptr, &tts);
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_tts) {
            rac::lifecycle::release_lifecycle_tts(&tts_ref);
        }
        rac_stt_result_free(&stt);
        rac_llm_result_free(&llm);
        if (have_lifecycle_llm) {
            rac::llm::release_lifecycle_llm(&llm_ref);
        }
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        d7_emit_error(handle, rc, "tts", "TTS synthesis failed", session_id, turn_id, request_id,
                      event_callback, user_data);
        emit_component_failure(handle, "tts", rc, "TTS synthesis failed");
        return rc;
    }

    d7_emit_audio(handle, tts.audio_data && tts.audio_size > 0 ? tts.audio_data : nullptr,
                  tts.audio_data && tts.audio_size > 0 ? tts.audio_size : 0,
                  tts.sample_rate > 0 ? tts.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE, true,
                  session_id, turn_id, request_id, event_callback, user_data);

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
                        llm.text);

    rac_stt_result_free(&stt);
    rac_llm_result_free(&llm);
    rac_tts_result_free(&tts);
    if (have_lifecycle_tts) {
        rac::lifecycle::release_lifecycle_tts(&tts_ref);
    }
    if (have_lifecycle_llm) {
        rac::llm::release_lifecycle_llm(&llm_ref);
    }
    if (have_lifecycle_stt) {
        rac::lifecycle::release_lifecycle_stt(&stt_ref);
    }
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
