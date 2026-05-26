/**
 * @file voice_agent_internal_helpers.h
 * @brief Shared internal helpers used by every voice-agent TU.
 *
 * NOT part of the public C ABI; only files under
 * `src/features/voice_agent/` may include this header.
 *
 * commons-features-voice-003 (SRP split): the original 2,291-LoC
 * `voice_agent.cpp` mixed lifecycle, model loading, legacy non-proto ABI,
 * generated-proto ABI, Wave D-7 full-session ABI, audio pipeline state
 * machine, and the shared emit/state-snapshot helpers in one translation
 * unit. This header is the contract through which the new per-ABI TUs
 * share access to the helpers; the helper implementations live in
 * `voice_agent_internal_helpers.cpp`.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H
#define RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H

#include <string>

#include "rac/core/rac_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "sdk_events.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

namespace rac::voice_agent::detail {

#if defined(RAC_HAVE_PROTOBUF)

// Validate that a (bytes, size) pair is decodable by Protobuf's
// ParseFromArray (non-null when size > 0; size within int range).
bool proto_bytes_valid(const uint8_t* bytes, size_t size);

// Return a non-null pointer suitable for `ParseFromArray`. Returns a
// pointer to a static empty string when size == 0.
const void* proto_parse_data(const uint8_t* bytes, size_t size);

// Serialize `message` into `out`. Returns RAC_SUCCESS on success or a
// `rac_proto_buffer_set_error`-derived error otherwise.
rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out);

// Build `<prefix>-<ms-since-epoch>`. Used to stamp turn/session ids on
// emitted voice events.
std::string event_id(const char* prefix);

// Snapshot the four-component readiness flags via the global lifecycle
// (with the per-handle component as a fallback for legacy-loaded models).
void fill_component_states(rac_voice_agent_handle_t handle,
                           runanywhere::v1::VoiceAgentComponentStates* out);

// Publish a serialized SDKEvent wrapping `voice_event` on the global
// SDKEvent queue with severity `severity`.
void publish_voice_pipeline_sdk_event(const runanywhere::v1::VoiceEvent& voice_event,
                                      runanywhere::v1::ErrorSeverity severity);

// Fan an emitted VoiceEvent out to both the registered proto callback
// (via rac::voice_agent::dispatch_proto_voice_event) AND the SDKEvent
// queue. `sdk_severity` controls the SDKEvent severity wrapper.
void emit_generated_voice_event(
    rac_voice_agent_handle_t handle, const runanywhere::v1::VoiceEvent& event,
    runanywhere::v1::ErrorSeverity sdk_severity = runanywhere::v1::ERROR_SEVERITY_INFO);

// Build + emit a component-state-changed VoiceEvent for `handle`.
void emit_component_states(rac_voice_agent_handle_t handle);

// Build + emit a turn lifecycle VoiceEvent.
void emit_turn_lifecycle(rac_voice_agent_handle_t handle,
                         runanywhere::v1::TurnLifecycleEventKind kind,
                         const char* transcript = nullptr, const char* response = nullptr,
                         const char* error = nullptr);

// Build + emit a session-error VoiceEvent + publish an SDKEvent failure.
void emit_component_failure(rac_voice_agent_handle_t handle, const char* component,
                            rac_result_t code, const char* message);

// Translate a proto `VoiceAgentComposeConfig` into the C ABI
// `rac_voice_agent_config_t`. The returned config aliases string pointers
// in `proto`; caller must keep `proto` alive across the use.
rac_voice_agent_config_t config_from_proto(const runanywhere::v1::VoiceAgentComposeConfig& proto);

#endif  // RAC_HAVE_PROTOBUF

// Validate all four voice-agent modalities are READY (lifecycle preferred,
// per-handle component as legacy fallback). Public to the voice-agent TUs
// so both the legacy non-proto path and the proto path can gate execution
// uniformly (commons-features-voice-004).
rac_result_t validate_all_components_ready(rac_voice_agent_handle_t handle);

}  // namespace rac::voice_agent::detail

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H
