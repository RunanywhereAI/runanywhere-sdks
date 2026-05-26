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
#include <mutex>

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
#include "rac/foundation/rac_proto_buffer.h"

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

#include "voice_agent_internal.h"
#include "voice_agent_internal_helpers.h"

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
    // (level-1 impl + ops); fall back to the per-handle component for legacy
    // load paths.
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
