/**
 * @file voice_agent.cpp
 * @brief RunAnywhere Commons - Voice Agent Implementation
 *
 * C++ port of Swift's VoiceAgentCapability.swift from:
 * Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 *
 * Lifecycle-acquire pattern (SWIFT-VOICE-AGENT-001 / T16 / Path X):
 *
 *   All proto-byte entry points (`rac_voice_agent_*_proto`) MUST resolve
 *   modality state via `acquire_lifecycle_{stt,tts,vad,llm}` instead of
 *   dereferencing `handle->{stt,llm,tts,vad}_handle`. The per-component
 *   handles stored on the agent are owned by the Swift bridge actor and
 *   are NOT the same as the level-1 (impl + ops) entries that
 *   `rac_model_lifecycle_load_proto` populates. Mirrors the precedent
 *   established in `rac_vlm_process_proto` (Phase 6j) where the
 *   component-handle pointer arithmetic produced an EXC_BAD_ACCESS on
 *   iPhone 17 Pro Max.
 *
 *   Legacy non-proto entry points (`rac_voice_agent_process_voice_turn`,
 *   `rac_voice_agent_process_stream`, individual `transcribe/`
 *   `generate_response/synthesize_speech/detect_speech` helpers) keep
 *   using `handle->*_handle` for backward compatibility. They are
 *   scheduled for removal in a follow-up cleanup (out of scope here).
 */

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

// SWIFT-VOICE-AGENT-001 (T16 / Path X) — voice agent proto path now consults
// the global model lifecycle (level 1: impl + ops) instead of dereferencing
// the per-component handles stored on the rac_voice_agent struct (level 3).
// Background: the iOS Swift bridge owns its component handles inside Swift
// actors and passes them to rac_voice_agent_create(...) for backward compat.
// When the user loads a model via `RunAnywhere.loadModel(...)` (the lifecycle
// path), only the global lifecycle service is populated -- the per-component
// handle passed at create time is never bound to the loaded model. The
// previous code path read `handle->stt_handle->state` etc. and reported
// `not_loaded` for every modality. Routing through `acquire_lifecycle_*`
// makes the proto API see the same state the lifecycle owns, matching the
// Phase 6j VLM precedent in `rac_vlm_process_proto`.
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "sdk_events.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

// v2 close-out Phase 2 — fan-out to GAP 09 proto-byte event ABI alongside
// the legacy struct callback. No-op when no proto callback is registered
// or when the build was configured without Protobuf.
#include "rac_voice_event_abi_internal.h"

// GAP 05 Phase 2 — VoiceAgent is the first GraphScheduler-driven consumer.
// `voice_agent_internal.h` now owns the rac_voice_agent struct layout so
// `voice_agent_pipeline.cpp` can read the component handles too.
#include "voice_agent_internal.h"

#include "voice_agent_pipeline.hpp"

namespace {
inline void rac_va_emit(rac_voice_agent_handle_t handle, const rac_voice_agent_event_t* event,
                        rac_voice_agent_event_callback_fn cb, void* user_data) {
    if (cb)
        cb(event, user_data);
    rac::voice_agent::dispatch_proto_event(handle, event);
}

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

// T16/Path X: probe the global lifecycle for each modality. A successful
// acquire/release pair means the modality is READY (level-1 impl + ops are
// bound to a loaded model). Anything else -> NOT_LOADED.
//
// We can't distinguish LOADING vs. NOT_LOADED purely from the lifecycle
// snapshot (an in-progress load briefly holds an entry in non-READY state
// then transitions). For the proto path callers this is fine: they only
// gate execution on READY anyway. If a future caller needs LOADING
// granularity, extend the lifecycle bridge -- do not reintroduce the
// component-handle indirection here.
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

// Promote a NOT_LOADED lifecycle state to READY when the voice-agent's own
// component handle reports the modality as loaded. This is the same fallback
// pattern used by validate_all_components_ready: callers that loaded models
// through rac_voice_agent_load_*_model never registered with the global
// lifecycle, but the per-handle component is still authoritative for those
// flows.
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

void emit_generated_voice_event(
    rac_voice_agent_handle_t handle, const runanywhere::v1::VoiceEvent& event,
    runanywhere::v1::ErrorSeverity sdk_severity = runanywhere::v1::ERROR_SEVERITY_INFO) {
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
                         runanywhere::v1::TurnLifecycleEventKind kind,
                         const char* transcript = nullptr, const char* response = nullptr,
                         const char* error = nullptr) {
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
}  // namespace

// Forward declare event helpers from events.cpp
namespace rac::events {
void emit_voice_agent_stt_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_llm_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_tts_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_all_ready();
}  // namespace rac::events

// Note: the `rac_voice_agent` struct definition now lives in
// `voice_agent_internal.h` so the GAP 05 Phase 2 pipeline implementation
// can also read the component handles. See that header for field docs.
//
// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

// =============================================================================
// DEFENSIVE VALIDATION HELPERS
// =============================================================================

/**
 * @brief Validate a single modality is ready via the global lifecycle.
 *
 * Returns RAC_SUCCESS iff `acquire_lifecycle_*` succeeds (the modality
 * has a level-1 impl + ops bound to a loaded model).
 */
template <typename Ref, rac_result_t (*Acquire)(Ref*), void (*Release)(Ref*)>
static rac_result_t lifecycle_modality_ready(const char* name) {
    Ref ref;
    rac_result_t rc = Acquire(&ref);
    if (rc == RAC_SUCCESS) {
        Release(&ref);
        return RAC_SUCCESS;
    }
    RAC_LOG_DEBUG("VoiceAgent", "%s lifecycle is not loaded (rc=%d)", name, rc);
    return RAC_ERROR_NOT_INITIALIZED;
}

/**
 * @brief Fallback: validate via the legacy per-component handle.
 *
 * Mirrors the previous validate_component_ready helper. Used only by the
 * legacy non-proto entry points (Swift's pre-lifecycle bridge path) that
 * load via `rac_*_component_load_model` and never populate the global
 * lifecycle.
 */
static rac_result_t legacy_component_ready(const char* name, rac_handle_t handle,
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

/**
 * @brief Validate all voice agent components are ready for processing.
 *
 * SWIFT-VOICE-AGENT-001 (T16/Path X): prefer the global model lifecycle
 * (level 1: impl + ops) -- the only authoritative source for the proto
 * entry points and `RunAnywhere.loadModel(...)` flows. Falls back to the
 * legacy per-component handle check for callers that loaded via the
 * deprecated `rac_voice_agent_load_*_model` family (which writes through
 * the component handle but not the lifecycle).
 *
 * @param handle Voice agent handle (used only for the legacy fallback)
 * @return RAC_SUCCESS if all components are READY, error code otherwise
 */
static rac_result_t validate_all_components_ready(rac_voice_agent_handle_t handle) {
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

// =============================================================================
// LIFECYCLE API
// =============================================================================

rac_result_t rac_voice_agent_create_standalone(rac_voice_agent_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("VoiceAgent", "Creating standalone voice agent");

    rac_voice_agent* agent = new (std::nothrow) rac_voice_agent();
    if (!agent) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    agent->owns_components = true;

    // Create LLM component
    rac_result_t result = rac_llm_component_create(&agent->llm_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create LLM component");
        delete agent;
        return result;
    }

    // Create STT component
    result = rac_stt_component_create(&agent->stt_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create STT component");
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    // Create TTS component
    result = rac_tts_component_create(&agent->tts_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create TTS component");
        rac_stt_component_destroy(agent->stt_handle);
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    // Create VAD component
    result = rac_vad_component_create(&agent->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create VAD component");
        rac_tts_component_destroy(agent->tts_handle);
        rac_stt_component_destroy(agent->stt_handle);
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    RAC_LOG_INFO("VoiceAgent", "Standalone voice agent created with all components");

    *out_handle = agent;
    return RAC_SUCCESS;
}

// DEPRECATED. Prefer `rac_voice_agent_create_standalone()` plus
// `rac_model_lifecycle_load_proto(...)` for each modality. The 4-handle
// API is retained for the iOS Swift bridge, which still constructs its
// per-modality component handles inside actors and threads them through
// here. After SWIFT-VOICE-AGENT-001 (T16/Path X), proto entry points
// dispatch through the global lifecycle and ignore these stored handles
// entirely; only the legacy non-proto entry points still dereference
// them for backward compatibility. Removal is gated on T17/T18 (Swift
// migration).
rac_result_t rac_voice_agent_create(rac_handle_t llm_component_handle,
                                    rac_handle_t stt_component_handle,
                                    rac_handle_t tts_component_handle,
                                    rac_handle_t vad_component_handle,
                                    rac_voice_agent_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // All component handles are required (mirrors Swift's init)
    if (!llm_component_handle || !stt_component_handle || !tts_component_handle ||
        !vad_component_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_voice_agent* agent = new (std::nothrow) rac_voice_agent();
    if (!agent) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    agent->owns_components = false;  // External handles, don't destroy them
    // Stored for legacy non-proto entry points only. Proto path resolves
    // ops via `acquire_lifecycle_*` and never touches these fields.
    agent->llm_handle = llm_component_handle;
    agent->stt_handle = stt_component_handle;
    agent->tts_handle = tts_component_handle;
    agent->vad_handle = vad_component_handle;

    RAC_LOG_INFO("VoiceAgent", "Voice agent created with external handles (legacy compose API)");

    *out_handle = agent;
    return RAC_SUCCESS;
}

void rac_voice_agent_destroy(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return;
    }

    // Signal shutdown and wait for all in-flight operations (including lock-free ones)
    handle->is_shutting_down.store(true, std::memory_order_release);
    handle->is_configured.store(false, std::memory_order_release);

    // GAP 05 Phase 2 — propagate cancel to any GraphScheduler-driven
    // pipeline run currently in flight. commons-features-voice-003:
    // snapshot the shared_ptr under handle->pipeline_mutex (held only
    // while copying the control block) so we never race the
    // process_stream store/reset, then call cancel() OUTSIDE the lock.
    // The pipeline's cancel_all() is non-blocking and idempotent, so
    // racing destroy() against an in-flight run is safe once the
    // shared_ptr copy is established without UB.
    //
    // pass3-syn-090: First-pass snapshot may be empty if a process_stream
    // call won the outer mutex before destroy and has not yet stored its
    // pipeline. We always re-snapshot and re-cancel AFTER acquiring the
    // outer mutex below (cancel is idempotent) to close that gap. The
    // matching guard in process_stream (is_shutting_down check under the
    // outer mutex) ensures any process_stream call that observes the
    // shutdown flag bails out without storing a pipeline at all.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> pipeline_snapshot;
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        pipeline_snapshot = handle->pipeline;
    }
    if (pipeline_snapshot) {
        pipeline_snapshot->cancel();
    }

    // Spin-wait until all in-flight operations complete
    while (handle->in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }

    {
        std::lock_guard<std::mutex> lock(handle->mutex);

        // pass3-syn-090: re-snapshot pipeline under the outer mutex and
        // cancel again. If a process_stream call interleaved between the
        // first snapshot above and this lock acquire, it may have stored
        // a fresh pipeline before observing is_shutting_down. The outer
        // mutex's acquire here synchronizes with process_stream's release
        // when it dropped the mutex, so this snapshot sees any pipeline
        // stored by such a call. cancel() is non-blocking and idempotent.
        std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> late_snapshot;
        {
            std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
            late_snapshot = handle->pipeline;
        }
        if (late_snapshot && late_snapshot != pipeline_snapshot) {
            late_snapshot->cancel();
        }

        // Drop the pipeline before component handles so its nodes (which
        // call into stt/llm/tts/vad) cannot outlive the handles they use.
        // Reset under pipeline_mutex too: process_stream may still try to
        // assign here on another thread until is_shutting_down propagates.
        {
            std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
            handle->pipeline.reset();
        }

        if (handle->owns_components) {
            RAC_LOG_DEBUG("VoiceAgent", "Destroying owned component handles");
            if (handle->vad_handle)
                rac_vad_component_destroy(handle->vad_handle);
            if (handle->tts_handle)
                rac_tts_component_destroy(handle->tts_handle);
            if (handle->stt_handle)
                rac_stt_component_destroy(handle->stt_handle);
            if (handle->llm_handle)
                rac_llm_component_destroy(handle->llm_handle);
        }
    }

    // B-FL-13/B-FL-5-001 sibling fix: clear any lingering proto-stream
    // callback registration keyed by this voice-agent handle BEFORE freeing
    // the memory. Without this, heap-pointer reuse on the next
    // rac_voice_agent_create() inherits a stale CallbackSlot { fn, user_data,
    // seq } from the previous session, corrupting the wire-seq sequence on
    // the very first VoiceEvent dispatch.
    rac_voice_agent_set_proto_callback(handle, nullptr, nullptr);
    // commons-features-voice-002: spin-wait until every in-flight
    // dispatch_proto_event/dispatch_proto_voice_event invocation on another
    // thread has returned before freeing the handle memory. Without this,
    // a thread that copied the CallbackSlot before the unset above can
    // still be inside slot.fn() with a now-stale `handle`-derived
    // user_data pointer when the caller frees it. Mirrors
    // rac_vlm_proto_quiesce / rac_llm_proto_quiesce / rac_vad_proto_quiesce.
    rac_voice_agent_proto_quiesce();

    // All threads that held/waited on mutex have now exited
    delete handle;
    RAC_LOG_DEBUG("VoiceAgent", "Voice agent destroyed");
}

// =============================================================================
// MODEL LOADING API
// =============================================================================

rac_result_t rac_voice_agent_load_stt_model(rac_voice_agent_handle_t handle, const char* model_path,
                                            const char* model_id, const char* model_name) {
    if (!handle || !model_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading STT model");

    // Emit loading state
    rac::events::emit_voice_agent_stt_state_changed(RAC_VOICE_AGENT_STATE_LOADING, model_id,
                                                    nullptr);

    rac_result_t result =
        rac_stt_component_load_model(handle->stt_handle, model_path, model_id, model_name);

    if (result == RAC_SUCCESS) {
        rac::events::emit_voice_agent_stt_state_changed(RAC_VOICE_AGENT_STATE_LOADED, model_id,
                                                        nullptr);
        // Check if all components are now ready
        if (rac_stt_component_is_loaded(handle->stt_handle) == RAC_TRUE &&
            rac_llm_component_is_loaded(handle->llm_handle) == RAC_TRUE &&
            rac_tts_component_is_loaded(handle->tts_handle) == RAC_TRUE) {
            rac::events::emit_voice_agent_all_ready();
        }
    } else {
        rac::events::emit_voice_agent_stt_state_changed(RAC_VOICE_AGENT_STATE_ERROR, model_id,
                                                        "Failed to load STT model");
    }

    return result;
}

rac_result_t rac_voice_agent_load_llm_model(rac_voice_agent_handle_t handle, const char* model_path,
                                            const char* model_id, const char* model_name) {
    if (!handle || !model_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading LLM model");

    // Emit loading state
    rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_LOADING, model_id,
                                                    nullptr);

    rac_result_t result =
        rac_llm_component_load_model(handle->llm_handle, model_path, model_id, model_name);

    if (result == RAC_SUCCESS) {
        rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_LOADED, model_id,
                                                        nullptr);
        // Check if all components are now ready
        if (rac_stt_component_is_loaded(handle->stt_handle) == RAC_TRUE &&
            rac_llm_component_is_loaded(handle->llm_handle) == RAC_TRUE &&
            rac_tts_component_is_loaded(handle->tts_handle) == RAC_TRUE) {
            rac::events::emit_voice_agent_all_ready();
        }
    } else {
        rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_ERROR, model_id,
                                                        "Failed to load LLM model");
    }

    return result;
}

rac_result_t rac_voice_agent_load_tts_voice(rac_voice_agent_handle_t handle, const char* voice_path,
                                            const char* voice_id, const char* voice_name) {
    if (!handle || !voice_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading TTS voice");

    // Emit loading state
    rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_LOADING, voice_id,
                                                    nullptr);

    rac_result_t result =
        rac_tts_component_load_voice(handle->tts_handle, voice_path, voice_id, voice_name);

    if (result == RAC_SUCCESS) {
        rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_LOADED, voice_id,
                                                        nullptr);
        // Check if all components are now ready
        if (rac_stt_component_is_loaded(handle->stt_handle) == RAC_TRUE &&
            rac_llm_component_is_loaded(handle->llm_handle) == RAC_TRUE &&
            rac_tts_component_is_loaded(handle->tts_handle) == RAC_TRUE) {
            rac::events::emit_voice_agent_all_ready();
        }
    } else {
        rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_ERROR, voice_id,
                                                        "Failed to load TTS voice");
    }

    return result;
}

rac_result_t rac_voice_agent_is_stt_loaded(rac_voice_agent_handle_t handle,
                                           rac_bool_t* out_loaded) {
    if (!handle || !out_loaded) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_loaded = rac_stt_component_is_loaded(handle->stt_handle);
    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_is_llm_loaded(rac_voice_agent_handle_t handle,
                                           rac_bool_t* out_loaded) {
    if (!handle || !out_loaded) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_loaded = rac_llm_component_is_loaded(handle->llm_handle);
    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_is_tts_loaded(rac_voice_agent_handle_t handle,
                                           rac_bool_t* out_loaded) {
    if (!handle || !out_loaded) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_loaded = rac_tts_component_is_loaded(handle->tts_handle);
    return RAC_SUCCESS;
}

const char* rac_voice_agent_get_stt_model_id(rac_voice_agent_handle_t handle) {
    if (!handle)
        return nullptr;
    return rac_stt_component_get_model_id(handle->stt_handle);
}

const char* rac_voice_agent_get_llm_model_id(rac_voice_agent_handle_t handle) {
    if (!handle)
        return nullptr;
    return rac_llm_component_get_model_id(handle->llm_handle);
}

const char* rac_voice_agent_get_tts_voice_id(rac_voice_agent_handle_t handle) {
    if (!handle)
        return nullptr;
    return rac_tts_component_get_voice_id(handle->tts_handle);
}

rac_result_t rac_voice_agent_initialize(rac_voice_agent_handle_t handle,
                                        const rac_voice_agent_config_t* config) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Initializing Voice Agent");

    const rac_voice_agent_config_t* cfg = config ? config : &RAC_VOICE_AGENT_CONFIG_DEFAULT;

    // Step 1: Initialize VAD (mirrors Swift's initializeVAD)
    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    // Step 2: Initialize STT model (mirrors Swift's initializeSTTModel)
    if (cfg->stt_config.model_path && strlen(cfg->stt_config.model_path) > 0) {
        // Load the specified model
        RAC_LOG_INFO("VoiceAgent", "Loading STT model");
        result = rac_stt_component_load_model(handle->stt_handle, cfg->stt_config.model_path,
                                              cfg->stt_config.model_id, cfg->stt_config.model_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "STT component failed to initialize");
            return result;
        }
    }
    // If no model specified, we trust that one is already loaded (mirrors Swift)

    // Step 3: Initialize LLM model (mirrors Swift's initializeLLMModel)
    if (cfg->llm_config.model_path && strlen(cfg->llm_config.model_path) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Loading LLM model");
        result = rac_llm_component_load_model(handle->llm_handle, cfg->llm_config.model_path,
                                              cfg->llm_config.model_id, cfg->llm_config.model_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "LLM component failed to initialize");
            return result;
        }
    }

    // Step 4: Initialize TTS (mirrors Swift's initializeTTSVoice)
    if (cfg->tts_config.voice_path && strlen(cfg->tts_config.voice_path) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Initializing TTS");
        result = rac_tts_component_load_voice(handle->tts_handle, cfg->tts_config.voice_path,
                                              cfg->tts_config.voice_id, cfg->tts_config.voice_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "TTS component failed to initialize");
            return result;
        }
    }

    // Step 5: Verify all components ready (mirrors Swift's verifyAllComponentsReady)
    // Note: In the C API, we trust initialization succeeded

    handle->is_configured.store(true, std::memory_order_release);
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized successfully");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Initializing Voice Agent with already-loaded models");

    // Initialize VAD
    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    // Note: In C API, we trust that components are already initialized
    // The Swift version checks isModelLoaded properties

    handle->is_configured.store(true, std::memory_order_release);
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized with pre-loaded models");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // GAP 05 Phase 2 — cancel any in-flight pipeline BEFORE taking the
    // outer mutex; the pipeline run holds the same mutex while it drains
    // and cancel_all() is the only way out of a stalled stage.
    // commons-features-voice-003: snapshot under pipeline_mutex so the
    // shared_ptr copy is synchronized with process_stream's store/reset.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> pipeline_snapshot;
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        pipeline_snapshot = handle->pipeline;
    }
    if (pipeline_snapshot) {
        pipeline_snapshot->cancel();
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Cleaning up Voice Agent");

    // pass3-syn-090: re-snapshot pipeline under the outer mutex and cancel
    // again. A process_stream call may have won the outer mutex first and
    // stored a pipeline AFTER our pre-lock snapshot ran. The outer mutex's
    // acquire here synchronizes with process_stream's release when it
    // dropped the mutex, so this snapshot sees any pipeline stored by
    // such a call. cancel() is non-blocking and idempotent.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> late_snapshot;
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        late_snapshot = handle->pipeline;
    }
    if (late_snapshot && late_snapshot != pipeline_snapshot) {
        late_snapshot->cancel();
    }

    // Tear the pipeline down before the underlying components so its
    // worker threads cannot dispatch into stt/llm/tts/vad after cleanup.
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        handle->pipeline.reset();
    }

    // Cleanup all components (mirrors Swift's cleanup)
    rac_llm_component_cleanup(handle->llm_handle);
    rac_stt_component_cleanup(handle->stt_handle);
    rac_tts_component_cleanup(handle->tts_handle);
    // VAD uses stop + reset instead of cleanup
    rac_vad_component_stop(handle->vad_handle);
    rac_vad_component_reset(handle->vad_handle);

    handle->is_configured.store(false, std::memory_order_release);

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle, rac_bool_t* out_is_ready) {
    if (!handle || !out_is_ready) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Atomic read — no mutex needed for a simple state check
    *out_is_ready = handle->is_configured.load(std::memory_order_acquire) ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

// =============================================================================
// VOICE PROCESSING API
// =============================================================================

rac_result_t rac_voice_agent_process_voice_turn(rac_voice_agent_handle_t handle,
                                                const void* audio_data, size_t audio_size,
                                                rac_voice_agent_result_t* out_result) {
    if (!handle || !audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Hold lock for the entire pipeline to prevent TOCTOU races.
    // is_ready() uses the atomic is_configured (no mutex needed), and
    // detect_speech() doesn't use the mutex, so this doesn't block them.
    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        RAC_LOG_ERROR("VoiceAgent", "Voice Agent is not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t validation_result = validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process");
        return validation_result;
    }

    RAC_LOG_INFO("VoiceAgent", "Processing voice turn");

    // Initialize result
    memset(out_result, 0, sizeof(rac_voice_agent_result_t));

    // Step 1: Transcribe audio
    RAC_LOG_DEBUG("VoiceAgent", "Step 1: Transcribing audio");
    rac_stt_result_t stt_result = {};
    rac_result_t result;
    result = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size, nullptr,
                                          &stt_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "STT transcription failed");
        return result;
    }

    if (!stt_result.text || strlen(stt_result.text) == 0) {
        RAC_LOG_WARNING("VoiceAgent", "Empty transcription, skipping processing");
        rac_stt_result_free(&stt_result);
        return RAC_ERROR_INVALID_STATE;
    }

    RAC_LOG_INFO("VoiceAgent", "Transcription completed");

    // Step 2: Generate LLM response
    RAC_LOG_DEBUG("VoiceAgent", "Step 2: Generating LLM response");
    rac_llm_result_t llm_result = {};
    result = rac_llm_component_generate(handle->llm_handle, stt_result.text, nullptr, &llm_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "LLM generation failed");
        rac_stt_result_free(&stt_result);
        return result;
    }

    RAC_LOG_INFO("VoiceAgent", "LLM response generated");

    // Step 3: Synthesize speech
    RAC_LOG_DEBUG("VoiceAgent", "Step 3: Synthesizing speech");
    rac_tts_result_t tts_result = {};
    result =
        rac_tts_component_synthesize(handle->tts_handle, llm_result.text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "TTS synthesis failed");
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        return result;
    }

    // Step 4: Convert Float32 PCM to WAV format — no lock needed (pure computation)
    void* wav_data = nullptr;
    size_t wav_size = 0;

    if (tts_result.audio_data != nullptr && tts_result.audio_size > 0) {
        result = rac_audio_float32_to_wav(tts_result.audio_data, tts_result.audio_size,
                                          tts_result.sample_rate > 0 ? tts_result.sample_rate
                                                                     : RAC_TTS_DEFAULT_SAMPLE_RATE,
                                          &wav_data, &wav_size);

        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "Failed to convert audio to WAV format");
            rac_stt_result_free(&stt_result);
            rac_llm_result_free(&llm_result);
            rac_tts_result_free(&tts_result);
            return result;
        }

        RAC_LOG_DEBUG("VoiceAgent", "Converted PCM to WAV format");
    } else {
        RAC_LOG_DEBUG("VoiceAgent", "Platform TTS played audio directly — no PCM data to convert");
    }

    // Build result (mirrors Swift's VoiceAgentResult)
    out_result->speech_detected = RAC_TRUE;
    out_result->transcription = rac_strdup(stt_result.text);
    out_result->response = rac_strdup(llm_result.text);
    out_result->synthesized_audio = wav_data;
    out_result->synthesized_audio_size = wav_size;

    // Free intermediate results
    rac_stt_result_free(&stt_result);
    rac_llm_result_free(&llm_result);
    rac_tts_result_free(&tts_result);

    RAC_LOG_INFO("VoiceAgent", "Voice turn completed");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_process_stream(rac_voice_agent_handle_t handle, const void* audio_data,
                                            size_t audio_size,
                                            rac_voice_agent_event_callback_fn callback,
                                            void* user_data) {
    if (!handle || !audio_data || audio_size == 0 || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Hold lock for the entire pipeline to prevent TOCTOU races, mirroring
    // the legacy in-line orchestration. The GAP 05 Phase 2 pipeline drains
    // synchronously inside `run_once()`, so the lock duration is unchanged.
    std::lock_guard<std::mutex> lock(handle->mutex);

    // pass3-syn-090: bail out if destroy/cleanup has begun. The outer-mutex
    // acquire above synchronizes with destroy's release of the same mutex,
    // so the release-store of `is_shutting_down` performed before destroy
    // acquires the mutex is visible here. Without this check, a thread that
    // wins the outer mutex first can store a fresh pipeline after destroy
    // has already taken its cancel snapshot — leaving an uncancellable
    // in-flight run that destroy must block on for the full run_once
    // duration.
    if (handle->is_shutting_down.load(std::memory_order_acquire)) {
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = RAC_ERROR_NOT_INITIALIZED;
        rac_va_emit(handle, &error_event, callback, user_data);
        return RAC_ERROR_NOT_INITIALIZED;
    }

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = RAC_ERROR_NOT_INITIALIZED;
        rac_va_emit(handle, &error_event, callback, user_data);
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t validation_result = validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process stream");
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = validation_result;
        rac_va_emit(handle, &error_event, callback, user_data);
        return validation_result;
    }

    // GAP 05 Phase 2 — drive the request through the GraphScheduler-backed
    // VoiceAgentPipeline (VAD → STT → LLM → TTS → Sink). Each stage runs on
    // its own worker thread; bounded edges between stages provide
    // backpressure; cancel_all() (invoked from destroy/cleanup) tears the
    // graph down deterministically.
    auto pipeline =
        std::make_shared<rac::voice_agent::VoiceAgentPipeline>(handle, callback, user_data);
    // commons-features-voice-003: every store/reset of handle->pipeline goes
    // through pipeline_mutex so it is correctly synchronized with the
    // destroy/cleanup snapshots that read the same shared_ptr instance.
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        handle->pipeline = pipeline;
    }

    rac_result_t result = pipeline->run_once(audio_data, audio_size);

    // Drop the per-call pipeline so destroy()'s cancel path doesn't latch
    // onto a torn-down scheduler. Any future call constructs a fresh one.
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        handle->pipeline.reset();
    }
    return result;
}

// =============================================================================
// INDIVIDUAL COMPONENT ACCESS API
// =============================================================================

rac_result_t rac_voice_agent_transcribe(rac_voice_agent_handle_t handle, const void* audio_data,
                                        size_t audio_size, char** out_transcription) {
    if (!handle || !audio_data || audio_size == 0 || !out_transcription) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_stt_result_t stt_result = {};
    rac_result_t result = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size,
                                                       nullptr, &stt_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    *out_transcription = rac_strdup(stt_result.text);
    rac_stt_result_free(&stt_result);

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_generate_response(rac_voice_agent_handle_t handle, const char* prompt,
                                               char** out_response) {
    if (!handle || !prompt || !out_response) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_llm_result_t llm_result = {};
    rac_result_t result =
        rac_llm_component_generate(handle->llm_handle, prompt, nullptr, &llm_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    *out_response = rac_strdup(llm_result.text);
    rac_llm_result_free(&llm_result);

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_synthesize_speech(rac_voice_agent_handle_t handle, const char* text,
                                               void** out_audio, size_t* out_audio_size) {
    if (!handle || !text || !out_audio || !out_audio_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_tts_result_t tts_result = {};
    rac_result_t result =
        rac_tts_component_synthesize(handle->tts_handle, text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    // Platform TTS plays audio directly and returns no PCM data — skip conversion.
    if (tts_result.audio_data != nullptr && tts_result.audio_size > 0) {
        void* wav_data = nullptr;
        size_t wav_size = 0;
        result = rac_audio_float32_to_wav(tts_result.audio_data, tts_result.audio_size,
                                          tts_result.sample_rate > 0 ? tts_result.sample_rate
                                                                     : RAC_TTS_DEFAULT_SAMPLE_RATE,
                                          &wav_data, &wav_size);

        if (result != RAC_SUCCESS) {
            rac_tts_result_free(&tts_result);
            return result;
        }

        *out_audio = wav_data;
        *out_audio_size = wav_size;
    } else {
        *out_audio = nullptr;
        *out_audio_size = 0;
    }

    rac_tts_result_free(&tts_result);

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_detect_speech(rac_voice_agent_handle_t handle, const float* samples,
                                           size_t sample_count, rac_bool_t* out_speech_detected) {
    if (!handle || !samples || sample_count == 0 || !out_speech_detected) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check shutdown barrier (this is a lock-free path)
    if (handle->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    handle->in_flight.fetch_add(1, std::memory_order_acq_rel);

    // Re-check after incrementing to avoid TOCTOU with destroy
    if (handle->is_shutting_down.load(std::memory_order_acquire)) {
        handle->in_flight.fetch_sub(1, std::memory_order_acq_rel);
        return RAC_ERROR_INVALID_STATE;
    }

    // VAD doesn't require is_configured (mirrors Swift)
    rac_result_t result =
        rac_vad_component_process(handle->vad_handle, samples, sample_count, out_speech_detected);

    handle->in_flight.fetch_sub(1, std::memory_order_acq_rel);
    return result;
}

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

rac_result_t rac_voice_agent_initialize_proto(rac_voice_agent_handle_t handle,
                                              const uint8_t* config_proto_bytes,
                                              size_t config_proto_size,
                                              rac_proto_buffer_t* out_component_states) {
    if (!out_component_states) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle) {
        return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    if (!proto_bytes_valid(config_proto_bytes, config_proto_size)) {
        return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_DECODING_ERROR,
                                          "VoiceAgentComposeConfig bytes are invalid");
    }

    runanywhere::v1::VoiceAgentComposeConfig proto;
    if (!proto.ParseFromArray(proto_parse_data(config_proto_bytes, config_proto_size),
                              static_cast<int>(config_proto_size))) {
        return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VoiceAgentComposeConfig");
    }

    rac_voice_agent_config_t config = config_from_proto(proto);
    rac_vad_config_t vad_config = RAC_VAD_CONFIG_DEFAULT;
    vad_config.sample_rate = config.vad_config.sample_rate;
    vad_config.frame_length = config.vad_config.frame_length;
    vad_config.energy_threshold = config.vad_config.energy_threshold;
    if (handle->vad_handle) {
        (void)rac_vad_component_configure(handle->vad_handle, &vad_config);
    }

    rac_result_t rc = rac_voice_agent_initialize(handle, &config);
    runanywhere::v1::VoiceAgentComponentStates states;
    fill_component_states(handle, &states);
    emit_component_states(handle);
    if (rc != RAC_SUCCESS) {
        emit_component_failure(handle, "voice_agent", rc, "voice-agent initialization failed");
        return rac_proto_buffer_set_error(out_component_states, rc,
                                          "voice-agent initialization failed");
    }
    return copy_proto_message(states, out_component_states);
#endif
}

rac_result_t rac_voice_agent_component_states_proto(rac_voice_agent_handle_t handle,
                                                    rac_proto_buffer_t* out_component_states) {
    if (!out_component_states) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle) {
        return rac_proto_buffer_set_error(out_component_states, RAC_ERROR_INVALID_HANDLE,
                                          "voice-agent handle is required");
    }
    runanywhere::v1::VoiceAgentComponentStates states;
    fill_component_states(handle, &states);
    emit_component_states(handle);
    return copy_proto_message(states, out_component_states);
#endif
}

rac_result_t rac_voice_agent_process_voice_turn_proto(rac_voice_agent_handle_t handle,
                                                      const void* audio_data, size_t audio_size,
                                                      rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)audio_data;
    (void)audio_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle || !audio_data || audio_size == 0) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "voice turn requires handle and audio bytes");
    }
    if (!handle->is_configured.load(std::memory_order_acquire)) {
        emit_component_failure(handle, "voice_agent", RAC_ERROR_NOT_INITIALIZED,
                               "voice agent is not initialized");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "voice agent is not initialized");
    }

    runanywhere::v1::VoiceAgentComponentStates states;
    fill_component_states(handle, &states);
    if (states.stt_state() != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        emit_component_failure(handle, "stt", RAC_ERROR_NOT_INITIALIZED,
                               "STT component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "STT component is not loaded");
    }
    if (states.llm_state() != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        emit_component_failure(handle, "llm", RAC_ERROR_NOT_INITIALIZED,
                               "LLM component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "LLM component is not loaded");
    }
    if (states.tts_state() != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        emit_component_failure(handle, "tts", RAC_ERROR_NOT_INITIALIZED,
                               "TTS component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "TTS component is not loaded");
    }
    if (states.vad_state() != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        emit_component_failure(handle, "vad", RAC_ERROR_NOT_INITIALIZED,
                               "VAD component is not initialized");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_INITIALIZED,
                                          "VAD component is not initialized");
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    emit_component_states(handle);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_STARTED);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED);
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED);

    // SWIFT-VOICE-AGENT-001 (T16/Path X): prefer the global lifecycle
    // (level-1 impl + ops) for callers that loaded models via
    // rac_model_lifecycle_load_proto / RunAnywhere.loadModel; fall back to
    // the per-handle component when callers loaded via the voice-agent's
    // own rac_voice_agent_load_*_model family (which only writes the
    // component handle, not the lifecycle entry). Mirrors the Phase 6j VLM
    // precedent in rac_vlm_process_proto.
    rac::lifecycle::LifecycleSttRef stt_ref{};
    const bool have_lifecycle_stt = rac::lifecycle::acquire_lifecycle_stt(&stt_ref) == RAC_SUCCESS;

    rac_stt_result_t stt = {};
    rac_result_t rc;
    if (have_lifecycle_stt) {
        rac_stt_service_t stt_service{stt_ref.ops, stt_ref.impl, stt_ref.model_id};
        rc = rac_stt_transcribe(&stt_service, audio_data, audio_size, nullptr, &stt);
    } else {
        rc =
            rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size, nullptr, &stt);
    }
    if (rc != RAC_SUCCESS) {
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        emit_component_failure(handle, "stt", rc, "STT transcription failed");
        return rac_proto_buffer_set_error(out_result, rc, "STT transcription failed");
    }
    if (!stt.text || stt.text[0] == '\0') {
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        emit_component_failure(handle, "stt", RAC_ERROR_INVALID_STATE,
                               "STT transcription was empty");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "STT transcription was empty");
    }
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL,
                        stt.text);

    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED,
                        stt.text);

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
        emit_component_failure(handle, "llm", rc, "LLM generation failed");
        return rac_proto_buffer_set_error(out_result, rc, "LLM generation failed");
    }
    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED,
                        stt.text, llm.text);

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
        rac_llm_result_free(&llm);
        if (have_lifecycle_llm) {
            rac::llm::release_lifecycle_llm(&llm_ref);
        }
        rac_stt_result_free(&stt);
        if (have_lifecycle_stt) {
            rac::lifecycle::release_lifecycle_stt(&stt_ref);
        }
        emit_component_failure(handle, "tts", rc, "TTS synthesis failed");
        return rac_proto_buffer_set_error(out_result, rc, "TTS synthesis failed");
    }

    void* wav_data = nullptr;
    size_t wav_size = 0;
    if (tts.audio_data && tts.audio_size > 0) {
        rc = rac_audio_float32_to_wav(tts.audio_data, tts.audio_size,
                                      tts.sample_rate > 0 ? tts.sample_rate
                                                          : RAC_TTS_DEFAULT_SAMPLE_RATE,
                                      &wav_data, &wav_size);
        if (rc != RAC_SUCCESS) {
            rac_tts_result_free(&tts);
            if (have_lifecycle_tts) {
                rac::lifecycle::release_lifecycle_tts(&tts_ref);
            }
            rac_llm_result_free(&llm);
            if (have_lifecycle_llm) {
                rac::llm::release_lifecycle_llm(&llm_ref);
            }
            rac_stt_result_free(&stt);
            if (have_lifecycle_stt) {
                rac::lifecycle::release_lifecycle_stt(&stt_ref);
            }
            emit_component_failure(handle, "tts", rc, "TTS audio conversion failed");
            return rac_proto_buffer_set_error(out_result, rc, "TTS audio conversion failed");
        }
    }

    runanywhere::v1::VoiceAgentResult result;
    result.set_speech_detected(true);
    result.set_transcription(stt.text);
    if (llm.text) {
        result.set_assistant_response(llm.text);
    }
    if (wav_data && wav_size > 0) {
        result.set_synthesized_audio(wav_data, wav_size);
    }
    fill_component_states(handle, result.mutable_final_state());

    emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_COMPLETED, stt.text,
                        llm.text);

    std::free(wav_data);
    rac_tts_result_free(&tts);
    if (have_lifecycle_tts) {
        rac::lifecycle::release_lifecycle_tts(&tts_ref);
    }
    rac_llm_result_free(&llm);
    if (have_lifecycle_llm) {
        rac::llm::release_lifecycle_llm(&llm_ref);
    }
    rac_stt_result_free(&stt);
    if (have_lifecycle_stt) {
        rac::lifecycle::release_lifecycle_stt(&stt_ref);
    }
    return copy_proto_message(result, out_result);
#endif
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

void rac_voice_agent_result_free(rac_voice_agent_result_t* result) {
    if (!result) {
        return;
    }

    if (result->transcription) {
        free(result->transcription);
        result->transcription = nullptr;
    }

    if (result->response) {
        free(result->response);
        result->response = nullptr;
    }

    if (result->synthesized_audio) {
        free(result->synthesized_audio);
        result->synthesized_audio = nullptr;
    }

    result->synthesized_audio_size = 0;
    result->speech_detected = RAC_FALSE;
}

// =============================================================================
// AUDIO PIPELINE STATE API
// Ported from Swift's AudioPipelineState.swift
// =============================================================================

/**
 * @brief Get string representation of audio pipeline state
 *
 * Ported from Swift AudioPipelineState enum rawValue (lines 4-24)
 */
const char* rac_audio_pipeline_state_name(rac_audio_pipeline_state_t state) {
    switch (state) {
        case RAC_AUDIO_PIPELINE_IDLE:
            return "idle";
        case RAC_AUDIO_PIPELINE_LISTENING:
            return "listening";
        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
            return "processingSpeech";
        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
            return "generatingResponse";
        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
            return "playingTTS";
        case RAC_AUDIO_PIPELINE_COOLDOWN:
            return "cooldown";
        case RAC_AUDIO_PIPELINE_ERROR:
            return "error";
        default:
            return "unknown";
    }
}

/**
 * @brief Check if microphone can be activated in current state
 *
 * Ported from Swift AudioPipelineStateManager.canActivateMicrophone() (lines 75-89)
 */
rac_bool_t rac_audio_pipeline_can_activate_microphone(rac_audio_pipeline_state_t current_state,
                                                      int64_t last_tts_end_time_ms,
                                                      int64_t cooldown_duration_ms) {
    // Only allow in idle or listening states
    switch (current_state) {
        case RAC_AUDIO_PIPELINE_IDLE:
        case RAC_AUDIO_PIPELINE_LISTENING:
            // Check cooldown if we recently finished TTS
            if (last_tts_end_time_ms > 0) {
                // Get current time in milliseconds
                int64_t now_ms = rac_get_current_time_ms();
                int64_t elapsed_ms = now_ms - last_tts_end_time_ms;
                if (elapsed_ms < cooldown_duration_ms) {
                    return RAC_FALSE;  // Still in cooldown
                }
            }
            return RAC_TRUE;

        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
        case RAC_AUDIO_PIPELINE_COOLDOWN:
        case RAC_AUDIO_PIPELINE_ERROR:
            return RAC_FALSE;

        default:
            return RAC_FALSE;
    }
}

/**
 * @brief Check if TTS can be played in current state
 *
 * Ported from Swift AudioPipelineStateManager.canPlayTTS() (lines 92-99)
 */
rac_bool_t rac_audio_pipeline_can_play_tts(rac_audio_pipeline_state_t current_state) {
    // TTS can only be played when we're generating a response
    return (current_state == RAC_AUDIO_PIPELINE_GENERATING_RESPONSE) ? RAC_TRUE : RAC_FALSE;
}

/**
 * @brief Check if a state transition is valid
 *
 * Ported from Swift AudioPipelineStateManager.isValidTransition() (lines 152-201)
 */
rac_bool_t rac_audio_pipeline_is_valid_transition(rac_audio_pipeline_state_t from_state,
                                                  rac_audio_pipeline_state_t to_state) {
    // Any state can transition to error
    if (to_state == RAC_AUDIO_PIPELINE_ERROR) {
        return RAC_TRUE;
    }

    switch (from_state) {
        case RAC_AUDIO_PIPELINE_IDLE:
            // From idle: can go to listening, cooldown, or error
            return (to_state == RAC_AUDIO_PIPELINE_LISTENING ||
                    to_state == RAC_AUDIO_PIPELINE_COOLDOWN)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_LISTENING:
            // From listening: can go to idle, processingSpeech, or error
            return (to_state == RAC_AUDIO_PIPELINE_IDLE ||
                    to_state == RAC_AUDIO_PIPELINE_PROCESSING_SPEECH)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
            // From processingSpeech: can go to idle, generatingResponse, listening, or error
            return (to_state == RAC_AUDIO_PIPELINE_IDLE ||
                    to_state == RAC_AUDIO_PIPELINE_GENERATING_RESPONSE ||
                    to_state == RAC_AUDIO_PIPELINE_LISTENING)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
            // From generatingResponse: can go to playingTTS, idle, cooldown, or error
            return (to_state == RAC_AUDIO_PIPELINE_PLAYING_TTS ||
                    to_state == RAC_AUDIO_PIPELINE_IDLE || to_state == RAC_AUDIO_PIPELINE_COOLDOWN)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
            // From playingTTS: can go to cooldown, idle, or error
            return (to_state == RAC_AUDIO_PIPELINE_COOLDOWN || to_state == RAC_AUDIO_PIPELINE_IDLE)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_COOLDOWN:
            // From cooldown: can only go to idle or error
            return (to_state == RAC_AUDIO_PIPELINE_IDLE) ? RAC_TRUE : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_ERROR:
            // From error: can only go to idle (reset)
            return (to_state == RAC_AUDIO_PIPELINE_IDLE) ? RAC_TRUE : RAC_FALSE;

        default:
            return RAC_FALSE;
    }
}

// =============================================================================
// Wave D-7 - Full-session voice-agent ABI
// =============================================================================

#if defined(RAC_HAVE_PROTOBUF)
#include "stt_options.pb.h"
#include "tts_options.pb.h"

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
    publish_voice_pipeline_sdk_event(*event,
                                     event->severity() == runanywhere::v1::ERROR_SEVERITY_ERROR
                                         ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                         : runanywhere::v1::ERROR_SEVERITY_INFO);
}

void d7_emit_state(rac_voice_agent_handle_t handle, runanywhere::v1::PipelineState previous,
                   runanywhere::v1::PipelineState current, const std::string& session_id,
                   const std::string& turn_id, const std::string& request_id,
                   rac_voice_agent_turn_event_callback_fn cb, void* user_data) {
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
    return request_id.empty() ? event_id("turn") : request_id;
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
    d7_emit_vad(handle, runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                /*is_speech=*/true, session_id, turn_id, request_id, event_callback, user_data);

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_LISTENING,
                  runanywhere::v1::PIPELINE_STATE_PROCESSING_SPEECH, session_id, turn_id,
                  request_id, event_callback, user_data);

    // commons-features-voice-001: dispatch through lifecycle refs when the
    // canonical lifecycle bridge owns the loaded models; fall back to the
    // voice-agent's per-handle component for callers that loaded via
    // rac_voice_agent_load_*_model and never bound a global lifecycle model.
    // Both paths satisfy the component_states READY check above.
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
    d7_emit_vad(handle, runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                /*is_speech=*/false, session_id, turn_id, request_id, event_callback, user_data);
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

    d7_emit_state(handle, runanywhere::v1::PIPELINE_STATE_PLAYING_TTS,
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

    // commons-features-voice-001: prefer the canonical lifecycle STT ref so
    // transcribe works when callers loaded STT through the lifecycle bridge
    // and never bound the voice-agent's stt_handle. When the lifecycle ref
    // is not loaded (e.g. callers loaded via rac_voice_agent_load_stt_model
    // into the voice-agent's own component handle), fall back to the
    // component-handle dispatch path so the test/legacy contract still
    // works end-to-end.
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

    // commons-features-voice-001: prefer the canonical lifecycle TTS ref;
    // fall back to the voice-agent's tts_handle for callers that loaded TTS
    // through rac_voice_agent_load_tts_voice and never bound a global
    // lifecycle TTS model.
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
