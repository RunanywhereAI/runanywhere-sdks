/**
 * @file voice_agent_proto_abi.cpp
 * @brief Proto-byte C ABI for the synchronous voice-agent surface
 *        (initialize / component_states / process_voice_turn).
 *
 * Split out of voice_agent.cpp under commons-features-voice-003. Public
 * C ABI unchanged. Shared emit/state-snapshot helpers live in
 * `voice_agent_internal_helpers.h`.
 */

#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_model_lifecycle.h"
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
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "model_types.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

#include "voice_agent_internal.h"
#include "voice_agent_internal_helpers.h"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

// Catalogued default Silero VAD model id, seeded by every example app's
// catalog. Mirrors Swift `RunAnywhere.defaultVADModelID`.
constexpr const char* kDefaultVADModelID = "silero-vad";

// Ensure a VAD model is loaded in the canonical lifecycle before the voice
// agent session starts. When no `.voiceActivityDetection` model is current,
// load the catalogued default (`silero-vad`) so the orchestrator's
// speech-start / speech-end lifecycle events fire — the energy-based fallback
// emits none of them, so without this the session stays silent after init.
//
// Ports Swift `RunAnywhere.ensureDefaultVAD(modelID:)` down into commons so
// every SDK (Kotlin/Flutter/RN/Web) gets the behavior for free instead of each
// re-implementing the workaround. Idempotent and best-effort: a failed
// auto-load is logged, not fatal — init proceeds on the energy fallback.
void ensure_default_vad_loaded() {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return;
    }

    runanywhere::v1::CurrentModelRequest current_request;
    current_request.set_category(runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION);
    std::string current_bytes;
    if (!current_request.SerializeToString(&current_bytes)) {
        return;
    }
    rac_proto_buffer_t current_out;
    rac_proto_buffer_init(&current_out);
    if (rac_model_lifecycle_current_model_proto(
            reinterpret_cast<const uint8_t*>(current_bytes.data()), current_bytes.size(),
            &current_out) == RAC_SUCCESS &&
        current_out.status == RAC_SUCCESS && current_out.data) {
        runanywhere::v1::CurrentModelResult current_result;
        if (current_result.ParseFromArray(current_out.data,
                                          static_cast<int>(current_out.size)) &&
            current_result.found() && !current_result.model_id().empty()) {
            rac_proto_buffer_free(&current_out);
            return;
        }
    }
    rac_proto_buffer_free(&current_out);

    RAC_LOG_INFO("VoiceAgent", "Auto-loading default VAD '%s' for voice-agent session",
                 kDefaultVADModelID);

    runanywhere::v1::ModelLoadRequest load_request;
    load_request.set_model_id(kDefaultVADModelID);
    load_request.set_category(runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION);
    std::string load_bytes;
    if (!load_request.SerializeToString(&load_bytes)) {
        return;
    }
    rac_proto_buffer_t load_out;
    rac_proto_buffer_init(&load_out);
    const rac_result_t rc = rac_model_lifecycle_load_proto(
        registry, reinterpret_cast<const uint8_t*>(load_bytes.data()), load_bytes.size(),
        &load_out);
    bool loaded = false;
    std::string error_message;
    if (rc == RAC_SUCCESS && load_out.status == RAC_SUCCESS && load_out.data) {
        runanywhere::v1::ModelLoadResult load_result;
        if (load_result.ParseFromArray(load_out.data, static_cast<int>(load_out.size))) {
            loaded = load_result.success();
            error_message = load_result.error_message();
        }
    }
    rac_proto_buffer_free(&load_out);

    if (!loaded) {
        RAC_LOG_WARNING("VoiceAgent",
                        "Default VAD '%s' auto-load failed: %s — voice agent will use energy "
                        "fallback",
                        kDefaultVADModelID,
                        error_message.empty() ? "unknown error" : error_message.c_str());
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

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
    using namespace rac::voice_agent::detail;
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

    // Guarantee a VAD model is loaded in the canonical lifecycle before the
    // session starts so the orchestrator's speech-start / speech-end events
    // fire. Best-effort: falls back to the energy detector on failure.
    ensure_default_vad_loaded();

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
    using namespace rac::voice_agent::detail;
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
    using namespace rac::voice_agent::detail;
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

    // commons-042: admit under the in-flight barrier so rac_voice_agent_destroy's
    // drain loop covers this multi-second STT+LLM+TTS turn. Without it the proto
    // path read is_configured above outside the mutex, so a destroy that flipped
    // is_shutting_down after that read could tear the agent down while this turn
    // (and its deferred user-callback emits) is still running.
    InFlightGuard guard(handle);
    if (!guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "voice agent is shutting down");
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

    // commons-045: hold handle->mutex while the pipeline runs (serializes
    // against load/cleanup/destroy), but defer every user-visible event
    // dispatch to a queue and flush it AFTER the lock is released — the
    // emit_* helpers ultimately invoke the registered proto callback
    // synchronously, so dispatching while holding the outer mutex would
    // self-deadlock if the callback re-enters any handle-mutex API
    // (cleanup, destroy, load_*_model, ...).
    std::vector<std::function<void()>> pending_emits;
    auto flush_emits = [&pending_emits]() {
        for (auto& emit : pending_emits) {
            emit();
        }
        pending_emits.clear();
    };

    runanywhere::v1::VoiceAgentResult result;
    rac_result_t rc = RAC_SUCCESS;
    std::string error_message;
    rac_result_t error_code = RAC_SUCCESS;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);

        pending_emits.emplace_back([handle]() { emit_component_states(handle); });
        // commons-149: the synchronous one-shot path has no VAD-driven
        // speech detection between STARTED and STT, so only STARTED →
        // TRANSCRIPTION_FINAL → COMPLETED are meaningful here. The d7
        // path emits USER_SPEECH_STARTED/_ENDED around the actual VAD
        // boundary; matching that contract requires real speech timing
        // which this synchronous one-shot does not have.
        pending_emits.emplace_back([handle]() {
            emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_STARTED);
        });

        // SWIFT-VOICE-AGENT-001 (T16/Path X): prefer the global lifecycle
        // (level-1 impl + ops); fall back to the per-handle component for legacy
        // load paths.
        rac::lifecycle::LifecycleSttRef stt_ref{};
        const bool have_lifecycle_stt =
            rac::lifecycle::acquire_lifecycle_stt(&stt_ref) == RAC_SUCCESS;

        rac_stt_result_t stt = {};
        if (have_lifecycle_stt) {
            rac_stt_service_t stt_service{stt_ref.ops, stt_ref.impl, stt_ref.model_id};
            rc = rac_stt_transcribe(&stt_service, audio_data, audio_size, nullptr, &stt);
        } else {
            rc = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size, nullptr,
                                              &stt);
        }
        if (rc != RAC_SUCCESS) {
            if (have_lifecycle_stt) {
                rac::lifecycle::release_lifecycle_stt(&stt_ref);
            }
            const rac_result_t failure_code = rc;
            pending_emits.emplace_back([handle, failure_code]() {
                emit_component_failure(handle, "stt", failure_code, "STT transcription failed");
            });
            error_code = rc;
            error_message = "STT transcription failed";
            goto cleanup_and_return;
        }
        if (!stt.text || stt.text[0] == '\0') {
            rac_stt_result_free(&stt);
            if (have_lifecycle_stt) {
                rac::lifecycle::release_lifecycle_stt(&stt_ref);
            }
            pending_emits.emplace_back([handle]() {
                emit_component_failure(handle, "stt", RAC_ERROR_INVALID_STATE,
                                       "STT transcription was empty");
            });
            error_code = RAC_ERROR_INVALID_STATE;
            error_message = "STT transcription was empty";
            rc = error_code;
            goto cleanup_and_return;
        }
        {
            const std::string stt_text(stt.text);
            pending_emits.emplace_back([handle, stt_text]() {
                emit_turn_lifecycle(handle,
                                    runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL,
                                    stt_text.c_str());
            });
            pending_emits.emplace_back([handle, stt_text]() {
                emit_turn_lifecycle(
                    handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED,
                    stt_text.c_str());
            });
        }

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
            const rac_result_t failure_code = rc;
            pending_emits.emplace_back([handle, failure_code]() {
                emit_component_failure(handle, "llm", failure_code, "LLM generation failed");
            });
            error_code = rc;
            error_message = "LLM generation failed";
            goto cleanup_and_return;
        }
        {
            const std::string stt_text(stt.text);
            const std::string llm_text(llm.text ? llm.text : "");
            pending_emits.emplace_back([handle, stt_text, llm_text]() {
                emit_turn_lifecycle(
                    handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED,
                    stt_text.c_str(), llm_text.c_str());
            });
        }

        rac::lifecycle::LifecycleTtsRef tts_ref{};
        const bool have_lifecycle_tts =
            rac::lifecycle::acquire_lifecycle_tts(&tts_ref) == RAC_SUCCESS;

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
            const rac_result_t failure_code = rc;
            pending_emits.emplace_back([handle, failure_code]() {
                emit_component_failure(handle, "tts", failure_code, "TTS synthesis failed");
            });
            error_code = rc;
            error_message = "TTS synthesis failed";
            goto cleanup_and_return;
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
                const rac_result_t failure_code = rc;
                pending_emits.emplace_back([handle, failure_code]() {
                    emit_component_failure(handle, "tts", failure_code,
                                           "TTS audio conversion failed");
                });
                error_code = rc;
                error_message = "TTS audio conversion failed";
                goto cleanup_and_return;
            }
        }

        result.set_speech_detected(true);
        result.set_transcription(stt.text);
        if (llm.text) {
            result.set_assistant_response(llm.text);
        }
        if (wav_data && wav_size > 0) {
            result.set_synthesized_audio(wav_data, wav_size);
        }
        fill_component_states(handle, result.mutable_final_state());

        {
            const std::string stt_text(stt.text);
            const std::string llm_text(llm.text ? llm.text : "");
            pending_emits.emplace_back([handle, stt_text, llm_text]() {
                emit_turn_lifecycle(handle, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_COMPLETED,
                                    stt_text.c_str(), llm_text.c_str());
            });
        }

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
    }  // lock released here

    flush_emits();
    return copy_proto_message(result, out_result);

cleanup_and_return:
    flush_emits();
    return rac_proto_buffer_set_error(out_result, error_code, error_message.c_str());
#endif
}
