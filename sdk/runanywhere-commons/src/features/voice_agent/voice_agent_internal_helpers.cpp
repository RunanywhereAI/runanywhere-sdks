/**
 * @file voice_agent_internal_helpers.cpp
 * @brief Implementation of shared voice-agent helpers declared in
 *        `voice_agent_internal_helpers.h` (SRP split out of the legacy
 *        voice_agent.cpp).
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
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#if defined(RAC_HAVE_PROTOBUF)
#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

// Voice agent proto path consults the global model lifecycle (level 1:
// impl + ops) instead of dereferencing the per-component handles stored on
// the rac_voice_agent struct (level 3).
#include "rac_voice_event_abi_internal.h"
#include "voice_agent_internal.h"

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"

namespace rac::voice_agent::detail {

namespace {

std::string sanitize_spoken_answer(const std::string& text) {
    std::string sanitized;
    sanitized.reserve(text.size());
    bool pending_space = false;

    for (const unsigned char byte : text) {
        const bool is_ascii_whitespace = byte == ' ' || byte == '\t' || byte == '\n' ||
                                         byte == '\r' || byte == '\f' || byte == '\v';
        if (is_ascii_whitespace) {
            pending_space = !sanitized.empty();
            continue;
        }
        if (byte < 0x20 || byte == 0x7f) {
            continue;
        }
        if (pending_space) {
            sanitized.push_back(' ');
            pending_space = false;
        }
        sanitized.push_back(static_cast<char>(byte));
    }
    return sanitized;
}

}  // namespace

rac_llm_options_t make_voice_llm_options() {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.max_tokens = kVoiceAgentMaxTokens;
    options.temperature = kVoiceAgentTemperature;
    options.top_p = 1.0f;
    options.top_k = kVoiceAgentTopK;
    options.seed = kVoiceAgentSeed;
    options.system_prompt = kVoiceAgentSystemPrompt;
    options.disable_thinking = RAC_TRUE;
    return options;
}

VoiceResponseParts split_voice_response(const char* raw_text) {
    VoiceResponseParts parts;
    if (!raw_text) {
        return parts;
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    if (rac_llm_extract_thinking(raw_text, &response, &response_len, &thinking, &thinking_len) ==
        RAC_SUCCESS) {
        if (response) {
            parts.answer.assign(response, response_len);
        }
        if (thinking && thinking_len > 0) {
            parts.thinking.assign(thinking, thinking_len);
        }
    } else {
        parts.answer = raw_text;
    }

    // The extractor intentionally requires a closing tag. The stripping API
    // also drops a trailing unclosed reasoning block, which is essential for
    // voice output: a max-token cutoff must never make TTS read private chain
    // of thought aloud. It also removes additional complete blocks after the
    // first while the metadata above retains the first canonical trace.
    const char* stripped = nullptr;
    size_t stripped_len = 0;
    if (rac_llm_strip_thinking(raw_text, &stripped, &stripped_len) == RAC_SUCCESS && stripped) {
        parts.answer.assign(stripped, stripped_len);
    }
    parts.answer = sanitize_spoken_answer(parts.answer);
    return parts;
}

rac_result_t validate_voice_response(const VoiceResponseParts& response) {
    return response.answer.empty() ? RAC_ERROR_GENERATION_FAILED : RAC_SUCCESS;
}

// Per-handle in-flight admission guard. See the header for the
// race it closes. The flag/counter live on the rac_voice_agent struct, so
// rac_voice_agent_destroy's existing `while (handle->in_flight > 0)` drain
// loop now covers every long-running entry point that wraps its body here.
InFlightGuard::InFlightGuard(rac_voice_agent_handle_t handle) : handle_(handle) {
    if (!handle_ || handle_->is_shutting_down.load(std::memory_order_acquire)) {
        return;
    }
    handle_->in_flight.fetch_add(1, std::memory_order_acq_rel);
    // Re-check after incrementing to avoid TOCTOU with rac_voice_agent_destroy,
    // which sets is_shutting_down=true and then drains the counter.
    if (handle_->is_shutting_down.load(std::memory_order_acquire)) {
        handle_->in_flight.fetch_sub(1, std::memory_order_acq_rel);
        return;
    }
    admitted_ = true;
}

InFlightGuard::~InFlightGuard() {
    if (admitted_) {
        handle_->in_flight.fetch_sub(1, std::memory_order_acq_rel);
    }
}

#if defined(RAC_HAVE_PROTOBUF)

bool proto_bytes_valid(const uint8_t* bytes, size_t size) {
    return rac::proto::bytes_valid(bytes, size);
}

const void* proto_parse_data(const uint8_t* bytes, size_t size) {
    return rac::proto::parse_bytes(bytes, size);
}

rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize voice-agent proto result");
}

std::string event_id(const char* prefix) {
    return std::string(prefix) + "-" + std::to_string(rac_get_current_time_ms());
}

namespace {

// Probe the global lifecycle for each modality. A successful
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
    // Route through the events layer so voice-agent telemetry reaches the
    // telemetry + log sinks per the destination bitmask, not just public.
    (void)rac::events::publish_prebuilt(sdk_event);
}

void publish_voice_turn_metrics(double stt_ms, double llm_ms, double tts_ms, double end_to_end_ms,
                                int64_t tokens_generated, const char* session_id,
                                const char* model_id, const char* framework,
                                int32_t transcript_chars, int32_t response_chars,
                                rac_result_t error_code, const char* error_message) {
    const bool failed = (error_code != RAC_SUCCESS);
    runanywhere::v1::SDKEvent sdk_event;
    sdk_event.set_timestamp_ms(rac_get_current_time_ms());
    sdk_event.set_id(event_id("voice"));
    sdk_event.set_category(failed ? runanywhere::v1::EVENT_CATEGORY_ERROR
                                  : runanywhere::v1::EVENT_CATEGORY_VOICE_AGENT);
    sdk_event.set_component(runanywhere::v1::SDK_COMPONENT_VOICE_AGENT);
    sdk_event.set_severity(failed ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                  : runanywhere::v1::ERROR_SEVERITY_INFO);
    sdk_event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    sdk_event.set_source("cpp");
    sdk_event.set_operation_id("voice_agent.turn");
    // Common columns. session_id is a native envelope field; the MetricsEvent
    // proto has no model/framework/char fields, so those ride the properties
    // carrier (read back in the telemetry kMetrics extraction).
    if (session_id != nullptr && session_id[0] != '\0') {
        sdk_event.set_session_id(session_id);
    }
    if (model_id != nullptr && model_id[0] != '\0') {
        (*sdk_event.mutable_properties())["model_id"] = model_id;
    }
    if (framework != nullptr && framework[0] != '\0') {
        (*sdk_event.mutable_properties())["framework"] = framework;
    }
    if (transcript_chars > 0) {
        (*sdk_event.mutable_properties())["transcript_chars"] = std::to_string(transcript_chars);
    }
    if (response_chars > 0) {
        (*sdk_event.mutable_properties())["response_chars"] = std::to_string(response_chars);
    }

    auto* vp = sdk_event.mutable_voice_pipeline();
    vp->set_timestamp_us(rac_get_current_time_ms() * 1000);
    vp->set_severity(failed ? runanywhere::v1::ERROR_SEVERITY_ERROR
                            : runanywhere::v1::ERROR_SEVERITY_INFO);
    vp->set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
    auto* metrics = vp->mutable_metrics();
    if (stt_ms > 0.0)
        metrics->set_stt_final_ms(stt_ms);
    if (llm_ms > 0.0)
        metrics->set_llm_total_ms(llm_ms);
    if (tts_ms > 0.0)
        metrics->set_tts_total_ms(tts_ms);
    if (end_to_end_ms > 0.0)
        metrics->set_end_to_end_ms(end_to_end_ms);
    if (tokens_generated > 0)
        metrics->set_tokens_generated(tokens_generated);

    // On failure set the envelope SDKError so the telemetry extractor marks the
    // row Failed with the message/code (c_abi_code preferred for error_code).
    if (failed) {
        auto* err = sdk_event.mutable_error();
        err->set_c_abi_code(static_cast<int32_t>(error_code));
        err->set_message(error_message != nullptr && error_message[0] != '\0'
                             ? error_message
                             : "voice turn failed");
        err->set_component("voice");
        err->set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
    }
    (void)rac::events::publish_prebuilt(sdk_event);
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
    // VoiceSessionError.code now uses canonical ErrorCode from errors.proto.
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
