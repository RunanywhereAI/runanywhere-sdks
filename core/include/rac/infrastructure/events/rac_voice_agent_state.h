/**
 * @file rac_voice_agent_state.h
 * @brief Internal voice-agent component-state event helpers.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `internal`.
 *
 * Voice-agent component lifecycle state + the C++ emit helpers that publish
 * those state transitions as canonical proto SDKEvents
 * (ComponentInitializationEvent). Previously these lived in the legacy
 * rac_analytics_events.h; they were split out when the struct-based analytics
 * taxonomy was removed in favor of the unified proto event catalog.
 *
 * NOT part of any public SDK surface — used by the voice-agent feature layer
 * and implemented in core/events.cpp.
 */

#ifndef RAC_VOICE_AGENT_STATE_H
#define RAC_VOICE_AGENT_STATE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Voice agent component lifecycle state.
 * Used for VOICE_AGENT_*_STATE_CHANGED transitions.
 */
typedef enum rac_voice_agent_component_state {
    RAC_VOICE_AGENT_STATE_NOT_LOADED = 0,
    RAC_VOICE_AGENT_STATE_LOADING = 1,
    RAC_VOICE_AGENT_STATE_LOADED = 2,
    RAC_VOICE_AGENT_STATE_ERROR = 3,
} rac_voice_agent_component_state_t;

#ifdef __cplusplus
}  // extern "C"

namespace rac::events {

// Publish voice-agent component-state transitions as canonical proto SDKEvents
// (ComponentInitializationEvent). Implemented in core/events.cpp.
void emit_voice_agent_stt_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_llm_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_tts_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message);
void emit_voice_agent_all_ready();

}  // namespace rac::events
#endif  // __cplusplus

#endif  // RAC_VOICE_AGENT_STATE_H
