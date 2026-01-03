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
// INTERNAL STRUCTURE - Mirrors Swift's VoiceAgentCapability properties
// =============================================================================

struct rac_voice_agent {
    // State
    bool is_configured;

    // Whether we own the component handles (and should destroy them)
    bool owns_components;

    // Composed component handles
    rac_handle_t llm_handle;
    rac_handle_t stt_handle;
    rac_handle_t tts_handle;
    rac_handle_t vad_handle;

    // Thread safety
    std::mutex mutex;

    rac_voice_agent()
        : is_configured(false),
          owns_components(false),
          llm_handle(nullptr),
          stt_handle(nullptr),
          tts_handle(nullptr),
          vad_handle(nullptr) {}
};

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

// =============================================================================
// DEFENSIVE VALIDATION HELPERS
// =============================================================================

/**
 * @brief Validate that a component is ready for use
 *
 * Performs defensive checks:
 * 1. Handle is non-null
 * 2. Component is in LOADED state
 *
 * This provides early failure with clear error messages instead of
 * cryptic crashes from dangling pointers or uninitialized components.
 *
 * @param component_name Human-readable name for error messages
 * @param handle Component handle
 * @param get_state_fn Function to get component lifecycle state
 * @return RAC_SUCCESS if valid, error code otherwise
 */
static rac_result_t validate_component_ready(const char* component_name, rac_handle_t handle,
                                             rac_lifecycle_state_t (*get_state_fn)(rac_handle_t)) {
    if (handle == nullptr) {
        RAC_LOG_ERROR("VoiceAgent", "%s handle is null", component_name);
        return RAC_ERROR_INVALID_HANDLE;
    }

    rac_lifecycle_state_t state = get_state_fn(handle);
    if (state != RAC_LIFECYCLE_STATE_LOADED) {
        RAC_LOG_ERROR("VoiceAgent", "%s is not loaded (state: %s)", component_name,
                      rac_lifecycle_state_name(state));
        return RAC_ERROR_NOT_INITIALIZED;
    }

    return RAC_SUCCESS;
}

/**
 * @brief Validate all voice agent components are ready for processing
 *
 * Checks STT, LLM, and TTS components are properly loaded before
 * attempting voice processing. This provides early failure with clear
 * error messages instead of cryptic crashes from dangling pointers.
 *
 * @param handle Voice agent handle
 * @return RAC_SUCCESS if all components ready, error code otherwise
 */
static rac_result_t validate_all_components_ready(rac_voice_agent_handle_t handle) {
    rac_result_t result;

    // Validate STT component
    result = validate_component_ready("STT", handle->stt_handle, rac_stt_component_get_state);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Validate LLM component
    result = validate_component_ready("LLM", handle->llm_handle, rac_llm_component_get_state);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Validate TTS component
    result = validate_component_ready("TTS", handle->tts_handle, rac_tts_component_get_state);
    if (result != RAC_SUCCESS) {
        return result;
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

    rac_voice_agent* agent = new rac_voice_agent();
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
    agent->owns_components = false;  // External handles, don't destroy them
    agent->llm_handle = llm_component_handle;
    agent->stt_handle = stt_component_handle;
    agent->tts_handle = tts_component_handle;
    agent->vad_handle = vad_component_handle;

    RAC_LOG_INFO("VoiceAgent", "Voice agent created with external handles");

    *out_handle = agent;
    return RAC_SUCCESS;
}

void rac_voice_agent_destroy(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return;
    }

    // If we own the components, destroy them
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

    delete handle;
    RAC_LOG_DEBUG("VoiceAgent", "Voice agent destroyed");
}

// =============================================================================
// MODEL LOADING API
// =============================================================================

rac_result_t rac_voice_agent_load_stt_model(rac_voice_agent_handle_t handle, const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading STT model");

    // Emit loading state
    rac::events::emit_voice_agent_stt_state_changed(RAC_VOICE_AGENT_STATE_LOADING, model_id,
                                                    nullptr);

    rac_result_t result = rac_stt_component_load_model(handle->stt_handle, model_id, model_id, model_id);

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

rac_result_t rac_voice_agent_load_llm_model(rac_voice_agent_handle_t handle, const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading LLM model");

    // Emit loading state
    rac::events::emit_voice_agent_llm_state_changed(RAC_VOICE_AGENT_STATE_LOADING, model_id,
                                                    nullptr);

    rac_result_t result = rac_llm_component_load_model(handle->llm_handle, model_id, model_id, model_id);

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

rac_result_t rac_voice_agent_load_tts_voice(rac_voice_agent_handle_t handle, const char* voice_id) {
    if (!handle || !voice_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Loading TTS voice");

    // Emit loading state
    rac::events::emit_voice_agent_tts_state_changed(RAC_VOICE_AGENT_STATE_LOADING, voice_id,
                                                    nullptr);

    rac_result_t result = rac_tts_component_load_voice(handle->tts_handle, voice_id, voice_id, voice_id);

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
    if (cfg->stt_config.model_id && strlen(cfg->stt_config.model_id) > 0) {
        // Load the specified model
        RAC_LOG_INFO("VoiceAgent", "Loading STT model");
        result = rac_stt_component_load_model(handle->stt_handle, cfg->stt_config.model_id,
                                              cfg->stt_config.model_id, cfg->stt_config.model_id);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "STT component failed to initialize");
            return result;
        }
    }
    // If no model specified, we trust that one is already loaded (mirrors Swift)

    // Step 3: Initialize LLM model (mirrors Swift's initializeLLMModel)
    if (cfg->llm_config.model_id && strlen(cfg->llm_config.model_id) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Loading LLM model");
        result = rac_llm_component_load_model(handle->llm_handle, cfg->llm_config.model_id,
                                              cfg->llm_config.model_id, cfg->llm_config.model_id);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "LLM component failed to initialize");
            return result;
        }
    }

    // Step 4: Initialize TTS (mirrors Swift's initializeTTSVoice)
    // Note: TTS uses load_model with voice as model_id
    if (cfg->tts_config.voice && strlen(cfg->tts_config.voice) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Initializing TTS");
        result = rac_tts_component_load_voice(handle->tts_handle, cfg->tts_config.voice,
                                              cfg->tts_config.voice, cfg->tts_config.voice);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "TTS component failed to initialize");
            return result;
        }
    }

    // Step 5: Verify all components ready (mirrors Swift's verifyAllComponentsReady)
    // Note: In the C API, we trust initialization succeeded

    handle->is_configured = true;
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

    handle->is_configured = true;
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized with pre-loaded models");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Cleaning up Voice Agent");

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
        RAC_LOG_ERROR("VoiceAgent", "Voice Agent is not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Defensive validation: Verify all components are in LOADED state before processing
    // This catches issues like dangling handles or improperly initialized components
    rac_result_t validation_result = validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process");
        return validation_result;
    }

    RAC_LOG_INFO("VoiceAgent", "Processing voice turn");

    // Initialize result
    memset(out_result, 0, sizeof(rac_voice_agent_result_t));

    // Step 1: Transcribe audio (mirrors Swift's Step 1)
    RAC_LOG_DEBUG("VoiceAgent", "Step 1: Transcribing audio");

    rac_stt_result_t stt_result = {};
    rac_result_t result = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size,
                                                       nullptr,  // default options
                                                       &stt_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "STT transcription failed");
        return result;
    }

    if (!stt_result.text || strlen(stt_result.text) == 0) {
        RAC_LOG_WARNING("VoiceAgent", "Empty transcription, skipping processing");
        rac_stt_result_free(&stt_result);
        // Return invalid state to indicate empty input (mirrors Swift's emptyInput error)
        return RAC_ERROR_INVALID_STATE;
    }

    RAC_LOG_INFO("VoiceAgent", "Transcription completed");

    // Step 2: Generate LLM response (mirrors Swift's Step 2)
    RAC_LOG_DEBUG("VoiceAgent", "Step 2: Generating LLM response");

    rac_llm_result_t llm_result = {};
    result = rac_llm_component_generate(handle->llm_handle, stt_result.text,
                                        nullptr,  // default options
                                        &llm_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "LLM generation failed");
        rac_stt_result_free(&stt_result);
        return result;
    }

    RAC_LOG_INFO("VoiceAgent", "LLM response generated");

    // Step 3: Synthesize speech (mirrors Swift's Step 3)
    RAC_LOG_DEBUG("VoiceAgent", "Step 3: Synthesizing speech");

    rac_tts_result_t tts_result = {};
    result = rac_tts_component_synthesize(handle->tts_handle, llm_result.text,
                                          nullptr,  // default options
                                          &tts_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "TTS synthesis failed");
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        return result;
    }

    // Step 4: Convert Float32 PCM to WAV format for playback
    // TTS returns raw Float32 samples, but audio players need WAV format
    void* wav_data = nullptr;
    size_t wav_size = 0;
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

    // Build result (mirrors Swift's VoiceAgentResult)
    out_result->speech_detected = RAC_TRUE;
    out_result->transcription = rac_strdup(stt_result.text);
    out_result->response = rac_strdup(llm_result.text);
    out_result->synthesized_audio = wav_data;
    out_result->synthesized_audio_size = wav_size;

    // Free intermediate results (tts_result audio data is no longer needed since we have WAV)
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

    if (!handle->is_configured) {
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = RAC_ERROR_NOT_INITIALIZED;
        callback(&error_event, user_data);
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Defensive validation: Verify all components are in LOADED state before processing
    rac_result_t validation_result = validate_all_components_ready(handle);
    if (validation_result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Component validation failed - cannot process stream");
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = validation_result;
        callback(&error_event, user_data);
        return validation_result;
    }

    // Step 1: Transcribe
    rac_stt_result_t stt_result = {};
    rac_result_t result = rac_stt_component_transcribe(handle->stt_handle, audio_data, audio_size,
                                                       nullptr, &stt_result);

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
    result =
        rac_tts_component_synthesize(handle->tts_handle, llm_result.text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = result;
        callback(&error_event, user_data);
        return result;
    }

    // Step 4: Convert Float32 PCM to WAV format for playback
    void* wav_data = nullptr;
    size_t wav_size = 0;
    result = rac_audio_float32_to_wav(tts_result.audio_data, tts_result.audio_size,
                                      tts_result.sample_rate > 0 ? tts_result.sample_rate
                                                                 : RAC_TTS_DEFAULT_SAMPLE_RATE,
                                      &wav_data, &wav_size);

    if (result != RAC_SUCCESS) {
        rac_stt_result_free(&stt_result);
        rac_llm_result_free(&llm_result);
        rac_tts_result_free(&tts_result);
        rac_voice_agent_event_t error_event = {};
        error_event.type = RAC_VOICE_AGENT_EVENT_ERROR;
        error_event.data.error_code = result;
        callback(&error_event, user_data);
        return result;
    }

    // Emit audio synthesized event (with WAV data)
    rac_voice_agent_event_t audio_event = {};
    audio_event.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
    audio_event.data.audio.audio_data = wav_data;
    audio_event.data.audio.audio_size = wav_size;
    callback(&audio_event, user_data);

    // Emit final processed event
    rac_voice_agent_event_t processed_event = {};
    processed_event.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
    processed_event.data.result.speech_detected = RAC_TRUE;
    processed_event.data.result.transcription = rac_strdup(stt_result.text);
    processed_event.data.result.response = rac_strdup(llm_result.text);
    processed_event.data.result.synthesized_audio = wav_data;
    processed_event.data.result.synthesized_audio_size = wav_size;
    callback(&processed_event, user_data);

    // Free intermediate results (WAV data ownership transferred to processed_event)
    rac_stt_result_free(&stt_result);
    rac_llm_result_free(&llm_result);
    rac_tts_result_free(&tts_result);

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

    if (!handle->is_configured) {
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

    if (!handle->is_configured) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_tts_result_t tts_result = {};
    rac_result_t result =
        rac_tts_component_synthesize(handle->tts_handle, text, nullptr, &tts_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    // Convert Float32 PCM to WAV format for playback
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

    // Free the original PCM data
    rac_tts_result_free(&tts_result);

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
