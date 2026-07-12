/**
 * @file voice_agent_internal_helpers.h
 * @brief Shared internal helpers used by every voice-agent TU.
 *
 * NOT part of the public C ABI; only files under
 * `src/features/voice_agent/` may include this header.
 *
 * SRP split: the original `voice_agent.cpp` mixed lifecycle, model
 * loading, legacy non-proto ABI,
 * generated-proto ABI, full-session ABI, audio pipeline state
 * machine, and the shared emit/state-snapshot helpers in one translation
 * unit. This header is the contract through which the new per-ABI TUs
 * share access to the helpers; the helper implementations live in
 * `voice_agent_internal_helpers.cpp`.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H
#define RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H

#include <string>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "sdk_events.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

namespace rac::voice_agent::detail {

// Canonical split used by every voice-agent entry point. `answer` is the only
// text that may be rendered, stored in conversation history, or sent to TTS;
// `thinking` is retained separately for typed events/result metadata.
struct VoiceResponseParts {
    std::string answer;
    std::string thinking;
};

// Canonical deterministic, no-thinking generation policy used by both the
// one-shot text helper and the full STT -> LLM -> TTS turn.
rac_llm_options_t make_voice_llm_options();

// Extract thinking metadata and sanitize the speakable answer. The answer has
// reasoning blocks removed, ASCII control bytes discarded, and whitespace
// trimmed/collapsed so an empty result can be rejected before TTS.
VoiceResponseParts split_voice_response(const char* raw_text);

// A successful backend call with no speakable answer is still an LLM failure;
// callers must stop the turn instead of passing an empty string to TTS.
rac_result_t validate_voice_response(const VoiceResponseParts& response);

// RAII admission guard for every long-running voice-agent entry
// point (process_voice_turn{,_proto}, process_stream, process_turn_proto,
// transcribe_proto, synthesize_speech_proto, detect_speech). Implements the
// canonical TOCTOU-safe sequence the lock-free design relies on:
//   1. check handle->is_shutting_down before incrementing,
//   2. increment handle->in_flight,
//   3. re-check handle->is_shutting_down (publish-before-check race with
//      rac_voice_agent_destroy, which sets the flag then drains the counter),
//   4. RAII-decrement on scope exit.
// `rac_voice_agent_destroy` spin-waits on handle->in_flight > 0, so wrapping
// each entry point in this guard makes the shutdown barrier cover them all
// instead of only detect_speech. Mirrors VlmInFlightGuard (rac_vlm_proto_abi)
// and SDKEventInFlightGuard (event_publisher), but scoped per-handle because
// the voice-agent counter/flag live on the rac_voice_agent struct.
struct InFlightGuard {
    explicit InFlightGuard(rac_voice_agent_handle_t handle);
    ~InFlightGuard();
    // True when the increment succeeded and shutdown was not in progress;
    // entry points must early-return when this is false.
    bool admitted() const { return admitted_; }
    InFlightGuard(const InFlightGuard&) = delete;
    InFlightGuard& operator=(const InFlightGuard&) = delete;

   private:
    rac_voice_agent_handle_t handle_;
    bool admitted_{false};
};

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

// Publish a per-turn MetricsEvent (kMetrics) so the turn is recorded to
// telemetry under the "voice" modality. telemetry_records() only records
// voice-pipeline events whose payload is kMetrics, so turn lifecycle events
// alone never reach telemetry — this is the row the dashboard shows. On
// failure (error_code != RAC_SUCCESS) the envelope SDKError is set so the row
// is marked Failed with the message/code. Pass 0 for any unmeasured stage.
void publish_voice_turn_metrics(double stt_ms, double llm_ms, double tts_ms, double end_to_end_ms,
                                int64_t tokens_generated, const char* session_id,
                                const char* model_id, const char* framework,
                                int32_t transcript_chars, int32_t response_chars,
                                rac_result_t error_code, const char* error_message);

// Translate a proto `VoiceAgentComposeConfig` into the C ABI
// `rac_voice_agent_config_t`. The returned config aliases string pointers
// in `proto`; caller must keep `proto` alive across the use.
rac_voice_agent_config_t config_from_proto(const runanywhere::v1::VoiceAgentComposeConfig& proto);

// Run one complete VAD -> STT -> LLM -> TTS turn over a pre-segmented
// `audio` buffer (16 kHz mono PCM16). This is the shared pipeline core of
// the full-session ABI: `rac_voice_agent_process_turn_proto` calls it with
// the parsed turn request, and `rac_voice_agent_feed_audio_proto` calls it
// once the in-core segmenter closes an utterance. Emits the same d7
// VoiceEvents (component states, turn lifecycle, pipeline state, VAD, STT,
// LLM token, TTS audio) through @p event_callback (may be NULL — the
// per-handle proto callback still receives every event) and, when
// @p out_result is non-NULL, also fills a `VoiceAgentResult` carrying the
// transcript, response, and synthesized WAV for inline playback.
//
// Acquires `handle->mutex` internally. The caller owns admission
// (InFlightGuard) and the `is_configured` gate.
rac_result_t d7_process_utterance(rac_voice_agent_handle_t handle, const std::string& audio,
                                  const std::string& session_id, const std::string& turn_id,
                                  const std::string& request_id, const std::string& language_code,
                                  rac_voice_agent_turn_event_callback_fn event_callback,
                                  void* user_data, runanywhere::v1::VoiceAgentResult* out_result);

#endif  // RAC_HAVE_PROTOBUF

// Validate all four voice-agent modalities are READY (lifecycle preferred,
// per-handle component as legacy fallback). Public to the voice-agent TUs
// so both the legacy non-proto path and the proto path can gate execution
// uniformly.
rac_result_t validate_all_components_ready(rac_voice_agent_handle_t handle);

}  // namespace rac::voice_agent::detail

#endif  // RAC_FEATURES_VOICE_AGENT_VOICE_AGENT_INTERNAL_HELPERS_H
