/**
 * @file voice_agent_internal_helpers.cpp
 * @brief Implementation of shared voice-agent helpers declared in
 *        `voice_agent_internal_helpers.h` (commons-features-voice-003 SRP
 *        split out of the legacy 2,291-LoC voice_agent.cpp).
 */

#include "voice_agent_internal_helpers.h"

#include <chrono>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

// SWIFT-VOICE-AGENT-001 (T16 / Path X) — voice agent proto path consults
// the global model lifecycle (level 1: impl + ops) instead of dereferencing
// the per-component handles stored on the rac_voice_agent struct (level 3).
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"

#include "rac_voice_event_abi_internal.h"
#include "voice_agent_internal.h"

namespace rac::voice_agent::detail {

#if defined(RAC_HAVE_PROTOBUF)

bool proto_bytes_valid(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* proto_parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize voice-agent proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

std::string event_id(const char* prefix) {
    return std::string(prefix) + "-" + std::to_string(rac_get_current_time_ms());
}

namespace {

// T16/Path X: probe the global lifecycle for each modality. A successful
// acquire/release pair means the modality is READY (level-1 impl + ops are
// bound to a loaded model). Anything else -> NOT_LOADED.
runanywhere::v1::ComponentLifecycleState lifecycle_state_stt() {
    rac::lifecycle::LifecycleSttRef ref;
    if (rac::lifecycle::acquire_lifecycle_stt(&ref) == RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
    }
    return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
}

runanywhere::v1::ComponentLifecycleState lifecycle_state_llm() {
    rac::llm::LifecycleLlmRef ref;
    if (rac::llm::acquire_lifecycle_llm(&ref) == RAC_SUCCESS) {
        rac::llm::release_lifecycle_llm(&ref);
        return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
    }
    return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
}

runanywhere::v1::ComponentLifecycleState lifecycle_state_tts() {
    rac::lifecycle::LifecycleTtsRef ref;
    if (rac::lifecycle::acquire_lifecycle_tts(&ref) == RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
    }
    return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
}

runanywhere::v1::ComponentLifecycleState lifecycle_state_vad() {
    rac::lifecycle::LifecycleVadRef ref;
    if (rac::lifecycle::acquire_lifecycle_vad(&ref) == RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_vad(&ref);
        return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
    }
    return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
}

// Promote NOT_LOADED to READY when the voice-agent's per-handle component
// reports the modality loaded. Same fallback used by validate_all_components_ready.
runanywhere::v1::ComponentLifecycleState
promote_with_component(runanywhere::v1::ComponentLifecycleState lifecycle_state,
                       rac_handle_t component_handle,
                       rac_lifecycle_state_t (*get_state_fn)(rac_handle_t)) {
    if (lifecycle_state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY)
        return lifecycle_state;
    if (component_handle && get_state_fn &&
        get_state_fn(component_handle) == RAC_LIFECYCLE_STATE_LOADED) {
        return runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
    }
    return lifecycle_state;
}

}  // namespace

void fill_component_states(rac_voice_agent_handle_t handle,
                           runanywhere::v1::VoiceAgentComponentStates* out) {
    const auto stt = promote_with_component(
        lifecycle_state_stt(), handle ? handle->stt_handle : nullptr, rac_stt_component_get_state);
    const auto llm = promote_with_component(
        lifecycle_state_llm(), handle ? handle->llm_handle : nullptr, rac_llm_component_get_state);
    const auto tts = promote_with_component(
        lifecycle_state_tts(), handle ? handle->tts_handle : nullptr, rac_tts_component_get_state);
    const auto vad = promote_with_component(
        lifecycle_state_vad(), handle ? handle->vad_handle : nullptr, rac_vad_component_get_state);
    out->set_stt_state(stt);
    out->set_llm_state(llm);
    out->set_tts_state(tts);
    out->set_vad_state(vad);
    out->set_ready(stt == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY &&
                   llm == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY &&
                   tts == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY &&
                   vad == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY);
    out->set_any_loading(false);  // not exposed by the lifecycle bridge snapshot
}

void publish_voice_pipeline_sdk_event(const runanywhere::v1::VoiceEvent& voice_event,
                                      runanywhere::v1::ErrorSeverity severity) {
    runanywhere::v1::SDKEvent sdk_event;
    sdk_event.set_timestamp_ms(rac_get_current_time_ms());
    sdk_event.set_id(event_id("voice"));
    sdk_event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    sdk_event.set_component(runanywhere::v1::SDK_COMPONENT_VOICE_AGENT);
    sdk_event.set_severity(severity);
    sdk_event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    sdk_event.set_source("cpp");
    sdk_event.set_operation_id("voice_agent.pipeline");
    sdk_event.mutable_voice_pipeline()->CopyFrom(voice_event);
    const size_t size = sdk_event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 || sdk_event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void emit_generated_voice_event(rac_voice_agent_handle_t handle,
                                const runanywhere::v1::VoiceEvent& event,
                                runanywhere::v1::ErrorSeverity sdk_severity) {
    rac::voice_agent::dispatch_proto_voice_event(handle, event);
    publish_voice_pipeline_sdk_event(event, sdk_severity);
}

void emit_component_states(rac_voice_agent_handle_t handle) {
    runanywhere::v1::VoiceEvent event;
    event.set_timestamp_us(rac_get_current_time_ms() * 1000);
    event.set_category(runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    fill_component_states(handle, event.mutable_component_state_changed());
    emit_generated_voice_event(handle, event);
}

void emit_turn_lifecycle(rac_voice_agent_handle_t handle,
                         runanywhere::v1::TurnLifecycleEventKind kind, const char* transcript,
                         const char* response, const char* error) {
    runanywhere::v1::VoiceEvent event;
    event.set_timestamp_us(rac_get_current_time_ms() * 1000);
    event.set_category(error ? runanywhere::v1::EVENT_CATEGORY_ERROR
                             : runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    event.set_severity(error ? runanywhere::v1::ERROR_SEVERITY_ERROR
                             : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* turn = event.mutable_turn_lifecycle();
    turn->set_kind(kind);
    turn->set_turn_id(event_id("turn"));
    if (transcript)
        turn->set_transcript(transcript);
    if (response)
        turn->set_response(response);
    if (error)
        turn->set_error(error);
    emit_generated_voice_event(handle, event,
                               error ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                     : runanywhere::v1::ERROR_SEVERITY_INFO);
}

void emit_component_failure(rac_voice_agent_handle_t handle, const char* component,
                            rac_result_t code, const char* message) {
    runanywhere::v1::VoiceEvent event;
    event.set_timestamp_us(rac_get_current_time_ms() * 1000);
    event.set_category(runanywhere::v1::EVENT_CATEGORY_ERROR);
    event.set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
    event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* session_error = event.mutable_session_error();
    // IDL-08: VoiceSessionError.code now uses canonical ErrorCode from errors.proto.
    session_error->set_code(runanywhere::v1::ERROR_CODE_PROCESSING_FAILED);
    session_error->set_message(message ? message : rac_error_message(code));
    if (component) {
        session_error->set_failed_component(component);
    }
    emit_generated_voice_event(handle, event, runanywhere::v1::ERROR_SEVERITY_ERROR);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_FAILED, nullptr, nullptr,
                        message ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, component ? component : "voice_agent",
                                        "processVoiceTurn", RAC_TRUE);
}

rac_voice_agent_config_t config_from_proto(const runanywhere::v1::VoiceAgentComposeConfig& proto) {
    rac_voice_agent_config_t config = RAC_VOICE_AGENT_CONFIG_DEFAULT;
    config.stt_config.model_path =
        proto.has_stt_model_path() ? proto.stt_model_path().c_str() : nullptr;
    config.stt_config.model_id = proto.has_stt_model_id() ? proto.stt_model_id().c_str() : nullptr;
    config.stt_config.model_name =
        proto.has_stt_model_name() ? proto.stt_model_name().c_str() : nullptr;
    config.llm_config.model_path =
        proto.has_llm_model_path() ? proto.llm_model_path().c_str() : nullptr;
    config.llm_config.model_id = proto.has_llm_model_id() ? proto.llm_model_id().c_str() : nullptr;
    config.llm_config.model_name =
        proto.has_llm_model_name() ? proto.llm_model_name().c_str() : nullptr;
    config.tts_config.voice_path =
        proto.has_tts_voice_path() ? proto.tts_voice_path().c_str() : nullptr;
    config.tts_config.voice_id = proto.has_tts_voice_id() ? proto.tts_voice_id().c_str() : nullptr;
    config.tts_config.voice_name =
        proto.has_tts_voice_name() ? proto.tts_voice_name().c_str() : nullptr;
    config.vad_config.sample_rate =
        proto.vad_sample_rate() > 0 ? proto.vad_sample_rate() : RAC_VAD_DEFAULT_SAMPLE_RATE;
    config.vad_config.frame_length =
        proto.vad_frame_length() > 0.0f ? proto.vad_frame_length() : RAC_VAD_DEFAULT_FRAME_LENGTH;
    config.vad_config.energy_threshold = proto.vad_energy_threshold() > 0.0f
                                             ? proto.vad_energy_threshold()
                                             : RAC_VOICE_AGENT_VAD_CONFIG_DEFAULT.energy_threshold;
    config.wakeword_config.enabled = proto.wakeword_enabled() ? RAC_TRUE : RAC_FALSE;
    config.wakeword_config.model_path =
        proto.has_wakeword_model_path() ? proto.wakeword_model_path().c_str() : nullptr;
    config.wakeword_config.model_id =
        proto.has_wakeword_model_id() ? proto.wakeword_model_id().c_str() : nullptr;
    config.wakeword_config.wake_word =
        proto.has_wakeword_phrase() ? proto.wakeword_phrase().c_str() : nullptr;
    config.wakeword_config.threshold = proto.wakeword_threshold() > 0.0f
                                           ? proto.wakeword_threshold()
                                           : RAC_VOICE_AGENT_WAKEWORD_CONFIG_DEFAULT.threshold;
    config.wakeword_config.embedding_model_path =
        proto.has_wakeword_embedding_model_path() ? proto.wakeword_embedding_model_path().c_str()
                                                  : nullptr;
    config.wakeword_config.vad_model_path =
        proto.has_wakeword_vad_model_path() ? proto.wakeword_vad_model_path().c_str() : nullptr;
    return config;
}

#endif  // RAC_HAVE_PROTOBUF

// Common validation: STT + LLM + TTS lifecycle READY (with per-handle fallback).
namespace {

template <typename Ref, rac_result_t (*Acquire)(Ref*), void (*Release)(Ref*)>
rac_result_t lifecycle_modality_ready(const char* name) {
    Ref ref;
    rac_result_t rc = Acquire(&ref);
    if (rc == RAC_SUCCESS) {
        Release(&ref);
        return RAC_SUCCESS;
    }
    RAC_LOG_DEBUG("VoiceAgent", "%s lifecycle is not loaded (rc=%d)", name, rc);
    return RAC_ERROR_NOT_INITIALIZED;
}

rac_result_t legacy_component_ready(const char* name, rac_handle_t handle,
                                    rac_lifecycle_state_t (*get_state_fn)(rac_handle_t)) {
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    rac_lifecycle_state_t state = get_state_fn(handle);
    if (state != RAC_LIFECYCLE_STATE_LOADED) {
        RAC_LOG_ERROR("VoiceAgent", "%s component is not loaded (state: %s)", name,
                      rac_lifecycle_state_name(state));
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return RAC_SUCCESS;
}

}  // namespace

rac_result_t validate_all_components_ready(rac_voice_agent_handle_t handle) {
    // STT
    {
        rac_result_t rc = lifecycle_modality_ready<rac::lifecycle::LifecycleSttRef,
                                                   rac::lifecycle::acquire_lifecycle_stt,
                                                   rac::lifecycle::release_lifecycle_stt>("STT");
        if (rc != RAC_SUCCESS) {
            rc = legacy_component_ready("STT", handle ? handle->stt_handle : nullptr,
                                        rac_stt_component_get_state);
            if (rc != RAC_SUCCESS)
                return rc;
        }
    }
    // LLM
    {
        rac_result_t rc =
            lifecycle_modality_ready<rac::llm::LifecycleLlmRef, rac::llm::acquire_lifecycle_llm,
                                     rac::llm::release_lifecycle_llm>("LLM");
        if (rc != RAC_SUCCESS) {
            rc = legacy_component_ready("LLM", handle ? handle->llm_handle : nullptr,
                                        rac_llm_component_get_state);
            if (rc != RAC_SUCCESS)
                return rc;
        }
    }
    // TTS
    {
        rac_result_t rc = lifecycle_modality_ready<rac::lifecycle::LifecycleTtsRef,
                                                   rac::lifecycle::acquire_lifecycle_tts,
                                                   rac::lifecycle::release_lifecycle_tts>("TTS");
        if (rc != RAC_SUCCESS) {
            rc = legacy_component_ready("TTS", handle ? handle->tts_handle : nullptr,
                                        rac_tts_component_get_state);
            if (rc != RAC_SUCCESS)
                return rc;
        }
    }
    return RAC_SUCCESS;
}

}  // namespace rac::voice_agent::detail
