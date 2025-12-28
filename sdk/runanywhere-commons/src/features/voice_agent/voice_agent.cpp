/**
 * @file voice_agent.cpp
 * @brief RunAnywhere Commons - Voice Agent Implementation
 *
 * C++ port of Swift's VoiceAgentCapability.swift from:
 * Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 */

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_platform_adapter.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"

// =============================================================================
// INTERNAL STRUCTURE - Mirrors Swift's VoiceAgentCapability properties
// =============================================================================

struct rac_voice_agent {
    // State
    bool is_configured;

    // Composed component handles
    rac_handle_t llm_handle;
    rac_handle_t stt_handle;
    rac_handle_t tts_handle;
    rac_handle_t vad_handle;

    // Thread safety
    std::mutex mutex;
};

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

// =============================================================================
// LIFECYCLE API
// =============================================================================

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

    rac_voice_agent* agent = new rac_voice_agent();
    agent->is_configured = false;
    agent->llm_handle = llm_component_handle;
    agent->stt_handle = stt_component_handle;
    agent->tts_handle = tts_component_handle;
    agent->vad_handle = vad_component_handle;

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Voice agent created");

    *out_handle = agent;
    return RAC_SUCCESS;
}

void rac_voice_agent_destroy(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return;
    }

    // Note: We don't destroy the component handles - they're owned externally
    // This mirrors Swift where the capabilities are passed by reference
    delete handle;

    rac_log(RAC_LOG_DEBUG, "VoiceAgent", "Voice agent destroyed");
}

rac_result_t rac_voice_agent_initialize(rac_voice_agent_handle_t handle,
                                        const rac_voice_agent_config_t* config) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Initializing Voice Agent");

    const rac_voice_agent_config_t* cfg = config ? config : &RAC_VOICE_AGENT_CONFIG_DEFAULT;

    // Step 1: Initialize VAD (mirrors Swift's initializeVAD)
    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    // Step 2: Initialize STT model (mirrors Swift's initializeSTTModel)
    if (cfg->stt_config.model_id && strlen(cfg->stt_config.model_id) > 0) {
        // Load the specified model
        rac_log(RAC_LOG_INFO, "VoiceAgent", "Loading STT model");
        result = rac_stt_component_load_model(handle->stt_handle, cfg->stt_config.model_id);
        if (result != RAC_SUCCESS) {
            rac_log(RAC_LOG_ERROR, "VoiceAgent", "STT component failed to initialize");
            return result;
        }
    }
    // If no model specified, we trust that one is already loaded (mirrors Swift)

    // Step 3: Initialize LLM model (mirrors Swift's initializeLLMModel)
    if (cfg->llm_config.model_id && strlen(cfg->llm_config.model_id) > 0) {
        rac_log(RAC_LOG_INFO, "VoiceAgent", "Loading LLM model");
        result = rac_llm_component_load_model(handle->llm_handle, cfg->llm_config.model_id);
        if (result != RAC_SUCCESS) {
            rac_log(RAC_LOG_ERROR, "VoiceAgent", "LLM component failed to initialize");
            return result;
        }
    }

    // Step 4: Initialize TTS (mirrors Swift's initializeTTSVoice)
    // Note: TTS uses load_model with voice as model_id
    if (cfg->tts_config.voice && strlen(cfg->tts_config.voice) > 0) {
        rac_log(RAC_LOG_INFO, "VoiceAgent", "Initializing TTS");
        result = rac_tts_component_load_voice(handle->tts_handle, cfg->tts_config.voice);
        if (result != RAC_SUCCESS) {
            rac_log(RAC_LOG_ERROR, "VoiceAgent", "TTS component failed to initialize");
            return result;
        }
    }

    // Step 5: Verify all components ready (mirrors Swift's verifyAllComponentsReady)
    // Note: In the C API, we trust initialization succeeded

    handle->is_configured = true;
    rac_log(RAC_LOG_INFO, "VoiceAgent", "Voice Agent initialized successfully");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Initializing Voice Agent with already-loaded models");

    // Initialize VAD
    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    // Note: In C API, we trust that components are already initialized
    // The Swift version checks isModelLoaded properties

    handle->is_configured = true;
    rac_log(RAC_LOG_INFO, "VoiceAgent", "Voice Agent initialized with pre-loaded models");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Cleaning up Voice Agent");

    // Cleanup all components (mirrors Swift's cleanup)
    rac_llm_component_cleanup(handle->llm_handle);
    rac_stt_component_cleanup(handle->stt_handle);
    rac_tts_component_cleanup(handle->tts_handle);
    // VAD uses stop + reset instead of cleanup
    rac_vad_component_stop(handle->vad_handle);
    rac_vad_component_reset(handle->vad_handle);

    handle->is_configured = false;

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle, rac_bool_t* out_is_ready) {
    if (!handle || !out_is_ready) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_is_ready = handle->is_configured ? RAC_TRUE : RAC_FALSE;

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

    // Mirrors Swift's guard isConfigured
    if (!handle->is_configured) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "Voice Agent is not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Processing voice turn");

    // Initialize result
    memset(out_result, 0, sizeof(rac_voice_agent_result_t));

    // Step 1: Transcribe audio (mirrors Swift's Step 1)
    rac_log(RAC_LOG_DEBUG, "VoiceAgent", "Step 1: Transcribing audio");

    rac_stt_result_t stt_result = {};
    rac_result_t result = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size,
                                             nullptr,  // default options
                                             &stt_result);

    if (result != RAC_SUCCESS) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "STT transcription failed");
        return result;
    }

    if (!stt_result.text || strlen(stt_result.text) == 0) {
        rac_log(RAC_LOG_WARNING, "VoiceAgent", "Empty transcription, skipping processing");
        rac_stt_result_free(&stt_result);
        // Return invalid state to indicate empty input (mirrors Swift's emptyInput error)
        return RAC_ERROR_INVALID_STATE;
    }

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Transcription completed");

    // Step 2: Generate LLM response (mirrors Swift's Step 2)
    rac_log(RAC_LOG_DEBUG, "VoiceAgent", "Step 2: Generating LLM response");

    rac_llm_result_t llm_result = {};
    result = rac_llm_component_generate(handle->llm_handle, stt_result.text,
                              nullptr,  // default options
                              &llm_result);

    if (result != RAC_SUCCESS) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "LLM generation failed");
        rac_stt_result_free(&stt_result);
        return result;
    }

    rac_log(RAC_LOG_INFO, "VoiceAgent", "LLM response generated");

    // Step 3: Synthesize speech (mirrors Swift's Step 3)
    rac_log(RAC_LOG_DEBUG, "VoiceAgent", "Step 3: Synthesizing speech");

    rac_tts_result_t tts_result = {};
    result = rac_tts_component_synthesize(handle->tts_handle, llm_result.text,
                                nullptr,  // default options
                                &tts_result);

    if (result != RAC_SUCCESS) {
        rac_log(RAC_LOG_ERROR, "VoiceAgent", "TTS synthesis failed");
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        return result;
    }

    // Build result (mirrors Swift's VoiceAgentResult)
    out_result->speech_detected = RAC_TRUE;
    out_result->transcription = rac_strdup(stt_result.text);
    out_result->response = rac_strdup(llm_result.text);
    out_result->synthesized_audio = tts_result.audio_data;
    out_result->synthesized_audio_size = tts_result.audio_size;

    // Clear tts_result's ownership (we transferred it)
    tts_result.audio_data = nullptr;
    tts_result.audio_size = 0;

    // Free intermediate results
    rac_stt_result_free(&stt_result);
    rac_llm_result_free(&llm_result);

    rac_log(RAC_LOG_INFO, "VoiceAgent", "Voice turn completed");

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

    if (!handle->is_configured) {
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = RAC_ERROR_NOT_INITIALIZED;
        callback(&error_event, user_data);
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Step 1: Transcribe
    rac_stt_result_t stt_result = {};
    rac_result_t result =
        rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size, nullptr, &stt_result);

    if (result != RAC_SUCCESS) {
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = result;
        callback(&error_event, user_data);
        return result;
    }

    // Emit transcription event
    rac_voice_agent_event_t transcription_event = {};
    transcription_event.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
    transcription_event.data.transcription = stt_result.text;
    callback(&transcription_event, user_data);

    // Step 2: Generate response
    rac_llm_result_t llm_result = {};
    result = rac_llm_component_generate(handle->llm_handle, stt_result.text, nullptr, &llm_result);

    if (result != RAC_SUCCESS) {
        rac_stt_result_free(&stt_result);
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = result;
        callback(&error_event, user_data);
        return result;
    }

    // Emit response event
    rac_voice_agent_event_t response_event = {};
    response_event.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
    response_event.data.response = llm_result.text;
    callback(&response_event, user_data);

    // Step 3: Synthesize
    rac_tts_result_t tts_result = {};
    result = rac_tts_component_synthesize(handle->tts_handle, llm_result.text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = result;
        callback(&error_event, user_data);
        return result;
    }

    // Emit audio synthesized event
    rac_voice_agent_event_t audio_event = {};
    audio_event.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
    audio_event.data.audio.audio_data = tts_result.audio_data;
    audio_event.data.audio.audio_size = tts_result.audio_size;
    callback(&audio_event, user_data);

    // Emit final processed event
    rac_voice_agent_event_t processed_event = {};
    processed_event.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
    processed_event.data.result.speech_detected = RAC_TRUE;
    processed_event.data.result.transcription = rac_strdup(stt_result.text);
    processed_event.data.result.response = rac_strdup(llm_result.text);
    processed_event.data.result.synthesized_audio = tts_result.audio_data;
    processed_event.data.result.synthesized_audio_size = tts_result.audio_size;
    callback(&processed_event, user_data);

    // Clear tts_result ownership (transferred)
    tts_result.audio_data = nullptr;

    // Free intermediate results
    rac_stt_result_free(&stt_result);
    rac_llm_result_free(&llm_result);

    return RAC_SUCCESS;
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

    if (!handle->is_configured) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_stt_result_t stt_result = {};
    rac_result_t result =
        rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size, nullptr, &stt_result);

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

    if (!handle->is_configured) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_llm_result_t llm_result = {};
    rac_result_t result = rac_llm_component_generate(handle->llm_handle, prompt, nullptr, &llm_result);

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

    if (!handle->is_configured) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_tts_result_t tts_result = {};
    rac_result_t result = rac_tts_component_synthesize(handle->tts_handle, text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    *out_audio = tts_result.audio_data;
    *out_audio_size = tts_result.audio_size;

    // Transfer ownership, don't free
    tts_result.audio_data = nullptr;

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_detect_speech(rac_voice_agent_handle_t handle, const float* samples,
                                           size_t sample_count, rac_bool_t* out_speech_detected) {
    if (!handle || !samples || sample_count == 0 || !out_speech_detected) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // VAD doesn't require is_configured (mirrors Swift)
    rac_result_t result =
        rac_vad_component_process(handle->vad_handle, samples, sample_count, out_speech_detected);

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
