/**
 * @file voice_agent_legacy_abi.cpp
 * @brief Legacy non-proto voice-agent C ABI — scheduled for removal in
 *        commons-features-voice-007 once iOS Swift + Playground/linux-voice
 *        consumers migrate to the proto + Wave D-7 surfaces.
 *
 * Hosts:
 *   - model loading API (`rac_voice_agent_load_{stt,llm,tts}_*`,
 *     `rac_voice_agent_is_{stt,llm,tts}_loaded`,
 *     `rac_voice_agent_get_{stt,llm,tts}*_model_id`),
 *   - synchronous initialization helpers
 *     (`rac_voice_agent_initialize`, `_initialize_with_loaded_models`,
 *     `_cleanup`, `_is_ready`),
 *   - synchronous voice processing
 *     (`rac_voice_agent_process_voice_turn`, `_process_stream`),
 *   - individual-component access shortcuts
 *     (`rac_voice_agent_transcribe`, `_generate_response`,
 *     `_synthesize_speech`, `_detect_speech`),
 *   - the legacy result struct freeing helper
 *     (`rac_voice_agent_result_free`).
 *
 * Split out of voice_agent.cpp under commons-features-voice-003. Public
 * ABI unchanged; the rac_voice_agent struct definition + the
 * VoiceAgentPipeline forward-declaration live in voice_agent_internal.h /
 * voice_agent_pipeline.hpp.
 */

// commons-features-voice-007: this TU implements the deprecated legacy
// non-proto entry points declared with RAC_VOICE_AGENT_LEGACY_DEPRECATED.
// Suppress -Wdeprecated-declarations in our own definitions; external
// callers still see the warning at the call site.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif

#include "rac_voice_event_abi_internal.h"
#include "voice_agent_internal.h"
#include "voice_agent_internal_helpers.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <thread>

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
#include "voice_agent_pipeline.hpp"

namespace {

inline void rac_va_emit(rac_voice_agent_handle_t handle, const rac_voice_agent_event_t* event,
                        rac_voice_agent_event_callback_fn cb, void* user_data) {
    if (cb)
        cb(event, user_data);
    rac::voice_agent::dispatch_proto_event(handle, event);
}

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

    rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_LOADING, model_id,
                                                    nullptr);

    rac_result_t result =
        rac_llm_component_load_model(handle->llm_handle, model_path, model_id, model_name);

    if (result == RAC_SUCCESS) {
        rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_LOADED, model_id,
                                                        nullptr);
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

    rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_LOADING, voice_id,
                                                    nullptr);

    rac_result_t result =
        rac_tts_component_load_voice(handle->tts_handle, voice_path, voice_id, voice_name);

    if (result == RAC_SUCCESS) {
        rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_LOADED, voice_id,
                                                        nullptr);
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

rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Initializing Voice Agent with already-loaded models");

    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    handle->is_configured.store(true, std::memory_order_release);
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized with pre-loaded models");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle, rac_bool_t* out_is_ready) {
    if (!handle || !out_is_ready) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
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

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        RAC_LOG_ERROR("VoiceAgent", "Voice Agent is not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t validation_result =
        rac::voice_agent::detail::validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process");
        return validation_result;
    }

    RAC_LOG_INFO("VoiceAgent", "Processing voice turn");

    memset(out_result, 0, sizeof(rac_voice_agent_result_t));

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

    RAC_LOG_DEBUG("VoiceAgent", "Step 2: Generating LLM response");
    rac_llm_result_t llm_result = {};
    result = rac_llm_component_generate(handle->llm_handle, stt_result.text, nullptr, &llm_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "LLM generation failed");
        rac_stt_result_free(&stt_result);
        return result;
    }

    RAC_LOG_INFO("VoiceAgent", "LLM response generated");

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

    out_result->speech_detected = RAC_TRUE;
    out_result->transcription = rac_strdup(stt_result.text);
    out_result->response = rac_strdup(llm_result.text);
    out_result->synthesized_audio = wav_data;
    out_result->synthesized_audio_size = wav_size;

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

    std::lock_guard<std::mutex> lock(handle->mutex);

    // pass3-syn-090: bail out if destroy/cleanup has begun.
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

    rac_result_t validation_result =
        rac::voice_agent::detail::validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process stream");
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = validation_result;
        rac_va_emit(handle, &error_event, callback, user_data);
        return validation_result;
    }

    // GAP 05 Phase 2 — drive the request through the GraphScheduler-backed
    // VoiceAgentPipeline (VAD → STT → LLM → TTS → Sink).
    auto pipeline =
        std::make_shared<rac::voice_agent::VoiceAgentPipeline>(handle, callback, user_data);
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        handle->pipeline = pipeline;
    }

    rac_result_t result = pipeline->run_once(audio_data, audio_size);

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

    if (handle->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    handle->in_flight.fetch_add(1, std::memory_order_acq_rel);

    if (handle->is_shutting_down.load(std::memory_order_acquire)) {
        handle->in_flight.fetch_sub(1, std::memory_order_acq_rel);
        return RAC_ERROR_INVALID_STATE;
    }

    rac_result_t result =
        rac_vad_component_process(handle->vad_handle, samples, sample_count, out_speech_detected);

    handle->in_flight.fetch_sub(1, std::memory_order_acq_rel);
    return result;
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

#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
