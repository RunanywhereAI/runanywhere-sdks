/**
 * @file rac_voice_agent.h
 * @brief Voice Agent Capability - Full Voice Conversation Pipeline
 *
 * C port of Swift's VoiceAgentCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 *
 * Composes STT, LLM, TTS, and VAD capabilities for end-to-end voice processing.
 */

#ifndef RAC_VOICE_AGENT_H
#define RAC_VOICE_AGENT_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_llm_types.h"
#include "rac_stt_types.h"
#include "rac_tts_types.h"
#include "rac_vad_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Voice Agent Timing Defaults
// =============================================================================

/** Default timeout for waiting for speech input (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_SPEECH_TIMEOUT_SEC 10.0

/** Default maximum recording duration (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_MAX_RECORDING_DURATION_SEC 30.0

/** Default pause duration to end recording (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_END_OF_SPEECH_PAUSE_SEC 1.5

/** Maximum time to wait for LLM response (seconds) */
#define RAC_VOICE_AGENT_LLM_RESPONSE_TIMEOUT_SEC 30.0

/** Maximum time to wait for TTS synthesis (seconds) */
#define RAC_VOICE_AGENT_TTS_RESPONSE_TIMEOUT_SEC 15.0

// =============================================================================
// TYPES - Mirrors Swift's VoiceAgentConfiguration and VoiceAgentResult
// =============================================================================

/**
 * @brief Audio pipeline state - Mirrors Swift's AudioPipelineState enum
 *
 * Represents the current state of the audio pipeline to prevent feedback loops.
 * See: Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
typedef enum rac_audio_pipeline_state {
    RAC_AUDIO_PIPELINE_IDLE = 0,                /**< System is idle, ready to start listening */
    RAC_AUDIO_PIPELINE_LISTENING = 1,           /**< Actively listening for speech via VAD */
    RAC_AUDIO_PIPELINE_PROCESSING_SPEECH = 2,   /**< Processing detected speech with STT */
    RAC_AUDIO_PIPELINE_GENERATING_RESPONSE = 3, /**< Generating response with LLM */
    RAC_AUDIO_PIPELINE_PLAYING_TTS = 4,         /**< Playing TTS output */
    RAC_AUDIO_PIPELINE_COOLDOWN = 5, /**< Cooldown period after TTS to prevent feedback */
    RAC_AUDIO_PIPELINE_ERROR = 6     /**< Error state requiring reset */
} rac_audio_pipeline_state_t;

/**
 * @brief Get string representation of audio pipeline state
 *
 * @param state The pipeline state
 * @return State name string (static, do not free)
 */
RAC_API const char* rac_audio_pipeline_state_name(rac_audio_pipeline_state_t state);

/**
 * @brief Voice agent event types.
 * Mirrors Swift's VoiceAgentEvent enum.
 */
typedef enum rac_voice_agent_event_type {
    RAC_VOICE_AGENT_EVENT_PROCESSED = 0,         /**< Complete processing result */
    RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED = 1,     /**< VAD triggered (speech detected/ended) */
    RAC_VOICE_AGENT_EVENT_TRANSCRIPTION = 2,     /**< Transcription available from STT */
    RAC_VOICE_AGENT_EVENT_RESPONSE = 3,          /**< Response generated from LLM */
    RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED = 4, /**< Audio synthesized from TTS */
    RAC_VOICE_AGENT_EVENT_ERROR = 5              /**< Error occurred during processing */
} rac_voice_agent_event_type_t;

/**
 * @brief VAD configuration for voice agent.
 * Mirrors Swift's VADConfiguration.
 */
typedef struct rac_voice_agent_vad_config {
    /** Sample rate (default: 16000) */
    int32_t sample_rate;

    /** Frame length in seconds (default: 0.1) */
    float frame_length;

    /** Energy threshold (default: 0.005) */
    float energy_threshold;
} rac_voice_agent_vad_config_t;

/**
 * @brief Default VAD configuration.
 */
static const rac_voice_agent_vad_config_t RAC_VOICE_AGENT_VAD_CONFIG_DEFAULT = {
    .sample_rate = 16000, .frame_length = 0.1f, .energy_threshold = 0.005f};

/**
 * @brief STT configuration for voice agent.
 * Mirrors Swift's STTConfiguration.
 */
typedef struct rac_voice_agent_stt_config {
    /** Model path - file path used for loading (can be NULL to use already-loaded model) */
    const char* model_path;
    /** Model ID - identifier for telemetry (e.g., "whisper-base") */
    const char* model_id;
    /** Model name - human-readable name (e.g., "Whisper Base") */
    const char* model_name;
} rac_voice_agent_stt_config_t;

/**
 * @brief LLM configuration for voice agent.
 * Mirrors Swift's LLMConfiguration.
 */
typedef struct rac_voice_agent_llm_config {
    /** Model path - file path used for loading (can be NULL to use already-loaded model) */
    const char* model_path;
    /** Model ID - identifier for telemetry (e.g., "llama-3.2-1b") */
    const char* model_id;
    /** Model name - human-readable name (e.g., "Llama 3.2 1B Instruct") */
    const char* model_name;
} rac_voice_agent_llm_config_t;

/**
 * @brief TTS configuration for voice agent.
 * Mirrors Swift's TTSConfiguration.
 */
typedef struct rac_voice_agent_tts_config {
    /** Voice path - file path used for loading (can be NULL/empty to use already-loaded voice) */
    const char* voice_path;
    /** Voice ID - identifier for telemetry (e.g., "vits-piper-en_GB-alba-medium") */
    const char* voice_id;
    /** Voice name - human-readable name (e.g., "Piper TTS (British English)") */
    const char* voice_name;
} rac_voice_agent_tts_config_t;

/**
 * @brief Voice agent configuration.
 * Mirrors Swift's VoiceAgentConfiguration.
 */
typedef struct rac_voice_agent_config {
    /** VAD configuration */
    rac_voice_agent_vad_config_t vad_config;

    /** STT configuration */
    rac_voice_agent_stt_config_t stt_config;

    /** LLM configuration */
    rac_voice_agent_llm_config_t llm_config;

    /** TTS configuration */
    rac_voice_agent_tts_config_t tts_config;
} rac_voice_agent_config_t;

/**
 * @brief Default voice agent configuration.
 */
static const rac_voice_agent_config_t RAC_VOICE_AGENT_CONFIG_DEFAULT = {
    .vad_config = {.sample_rate = 16000, .frame_length = 0.1f, .energy_threshold = 0.005f},
    .stt_config = {.model_path = RAC_NULL, .model_id = RAC_NULL, .model_name = RAC_NULL},
    .llm_config = {.model_path = RAC_NULL, .model_id = RAC_NULL, .model_name = RAC_NULL},
    .tts_config = {.voice_path = RAC_NULL, .voice_id = RAC_NULL, .voice_name = RAC_NULL}};

// =============================================================================
// AUDIO PIPELINE STATE MANAGER CONFIG - Mirrors Swift's AudioPipelineStateManager.Configuration
// =============================================================================

/**
 * @brief Audio pipeline state manager configuration
 *
 * Mirrors Swift's AudioPipelineStateManager.Configuration struct.
 * See: Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
typedef struct rac_audio_pipeline_config {
    /** Duration to wait after TTS before allowing microphone (seconds) */
    float cooldown_duration;

    /** Whether to enforce strict state transitions */
    rac_bool_t strict_transitions;

    /** Maximum TTS duration before forced timeout (seconds) */
    float max_tts_duration;
} rac_audio_pipeline_config_t;

/**
 * @brief Default audio pipeline configuration
 */
static const rac_audio_pipeline_config_t RAC_AUDIO_PIPELINE_CONFIG_DEFAULT = {
    .cooldown_duration = 0.8f, /* 800ms - better feedback prevention */
    .strict_transitions = RAC_TRUE,
    .max_tts_duration = 30.0f};

// =============================================================================
// AUDIO PIPELINE STATE MANAGER API
// =============================================================================

/**
 * @brief Check if microphone can be activated in current state
 *
 * @param current_state Current pipeline state
 * @param last_tts_end_time_ms Last TTS end time in milliseconds since epoch (0 if none)
 * @param cooldown_duration_ms Cooldown duration in milliseconds
 * @return RAC_TRUE if microphone can be activated
 */
RAC_API rac_bool_t rac_audio_pipeline_can_activate_microphone(
    rac_audio_pipeline_state_t current_state, int64_t last_tts_end_time_ms,
    int64_t cooldown_duration_ms);

/**
 * @brief Check if TTS can be played in current state
 *
 * @param current_state Current pipeline state
 * @return RAC_TRUE if TTS can be played
 */
RAC_API rac_bool_t rac_audio_pipeline_can_play_tts(rac_audio_pipeline_state_t current_state);

/**
 * @brief Check if a state transition is valid
 *
 * @param from_state Current state
 * @param to_state Target state
 * @return RAC_TRUE if transition is valid
 */
RAC_API rac_bool_t rac_audio_pipeline_is_valid_transition(rac_audio_pipeline_state_t from_state,
                                                          rac_audio_pipeline_state_t to_state);

/**
 * @brief Voice agent processing result.
 * Mirrors Swift's VoiceAgentResult.
 */
typedef struct rac_voice_agent_result {
    /** Whether speech was detected in the input audio */
    rac_bool_t speech_detected;

    /** Transcribed text from STT (owned, must be freed with rac_free) */
    char* transcription;

    /** Generated response text from LLM (owned, must be freed with rac_free) */
    char* response;

    /** Synthesized audio data from TTS (owned, must be freed with rac_free) */
    void* synthesized_audio;

    /** Size of synthesized audio data in bytes */
    size_t synthesized_audio_size;
} rac_voice_agent_result_t;

/**
 * @brief Voice agent event data.
 * Contains union for different event types.
 */
typedef struct rac_voice_agent_event {
    /** Event type */
    rac_voice_agent_event_type_t type;

    union {
        /** For PROCESSED event */
        rac_voice_agent_result_t result;

        /** For VAD_TRIGGERED event: true if speech started, false if ended */
        rac_bool_t vad_speech_active;

        /** For TRANSCRIPTION event */
        const char* transcription;

        /** For RESPONSE event */
        const char* response;

        /** For AUDIO_SYNTHESIZED event */
        struct {
            const void* audio_data;
            size_t audio_size;
        } audio;

        /** For ERROR event */
        rac_result_t error_code;
    } data;
} rac_voice_agent_event_t;

/**
 * @brief Callback for voice agent events during streaming.
 *
 * @param event The event that occurred
 * @param user_data User-provided context
 */
typedef void (*rac_voice_agent_event_callback_fn)(const rac_voice_agent_event_t* event,
                                                  void* user_data);

// =============================================================================
// OPAQUE HANDLE
// =============================================================================

/**
 * @brief Opaque handle for voice agent instance.
 */
typedef struct rac_voice_agent* rac_voice_agent_handle_t;

// =============================================================================
// LIFECYCLE API
// =============================================================================

/**
 * @brief Create a standalone voice agent that owns its component handles.
 *
 * This is the recommended API. The voice agent creates and manages its own
 * STT, LLM, TTS, and VAD component handles internally. Use the model loading
 * APIs to load models after creation.
 *
 * @param out_handle Output: Handle to the created voice agent
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_create_standalone(rac_voice_agent_handle_t* out_handle);

/**
 * @brief Create a voice agent instance with external component handles.
 *
 * DEPRECATED: Prefer rac_voice_agent_create_standalone().
 * This API is for backward compatibility when you need to share handles.
 *
 * @param llm_component_handle Handle to LLM component (rac_llm_component)
 * @param stt_component_handle Handle to STT component (rac_stt_component)
 * @param tts_component_handle Handle to TTS component (rac_tts_component)
 * @param vad_component_handle Handle to VAD component (rac_vad_component)
 * @param out_handle Output: Handle to the created voice agent
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_create(rac_handle_t llm_component_handle,
                                            rac_handle_t stt_component_handle,
                                            rac_handle_t tts_component_handle,
                                            rac_handle_t vad_component_handle,
                                            rac_voice_agent_handle_t* out_handle);

/**
 * @brief Destroy a voice agent instance.
 *
 * If created with rac_voice_agent_create_standalone(), this also destroys
 * the owned component handles.
 *
 * @param handle Voice agent handle
 */
RAC_API void rac_voice_agent_destroy(rac_voice_agent_handle_t handle);

// =============================================================================
// MODEL LOADING API (for standalone voice agent)
// =============================================================================

/**
 * @brief Load an STT model into the voice agent.
 *
 * @param handle Voice agent handle
 * @param model_path File path to the model (used for loading)
 * @param model_id Model identifier (used for telemetry, e.g., "whisper-base")
 * @param model_name Human-readable model name (e.g., "Whisper Base")
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_load_stt_model(rac_voice_agent_handle_t handle,
                                                    const char* model_path,
                                                    const char* model_id,
                                                    const char* model_name);

/**
 * @brief Load an LLM model into the voice agent.
 *
 * @param handle Voice agent handle
 * @param model_path File path to the model (used for loading)
 * @param model_id Model identifier (used for telemetry, e.g., "llama-3.2-1b")
 * @param model_name Human-readable model name (e.g., "Llama 3.2 1B Instruct")
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_load_llm_model(rac_voice_agent_handle_t handle,
                                                    const char* model_path,
                                                    const char* model_id,
                                                    const char* model_name);

/**
 * @brief Load a TTS voice into the voice agent.
 *
 * @param handle Voice agent handle
 * @param voice_path File path to the voice (used for loading)
 * @param voice_id Voice identifier (used for telemetry, e.g., "vits-piper-en_GB-alba-medium")
 * @param voice_name Human-readable voice name (e.g., "Piper TTS (British English)")
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_load_tts_voice(rac_voice_agent_handle_t handle,
                                                    const char* voice_path,
                                                    const char* voice_id,
                                                    const char* voice_name);

/**
 * @brief Check if STT model is loaded.
 *
 * @param handle Voice agent handle
 * @param out_loaded Output: RAC_TRUE if loaded
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_is_stt_loaded(rac_voice_agent_handle_t handle,
                                                   rac_bool_t* out_loaded);

/**
 * @brief Check if LLM model is loaded.
 *
 * @param handle Voice agent handle
 * @param out_loaded Output: RAC_TRUE if loaded
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_is_llm_loaded(rac_voice_agent_handle_t handle,
                                                   rac_bool_t* out_loaded);

/**
 * @brief Check if TTS voice is loaded.
 *
 * @param handle Voice agent handle
 * @param out_loaded Output: RAC_TRUE if loaded
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_is_tts_loaded(rac_voice_agent_handle_t handle,
                                                   rac_bool_t* out_loaded);

/**
 * @brief Get the currently loaded STT model ID.
 *
 * @param handle Voice agent handle
 * @return Model ID string (static, do not free) or NULL if not loaded
 */
RAC_API const char* rac_voice_agent_get_stt_model_id(rac_voice_agent_handle_t handle);

/**
 * @brief Get the currently loaded LLM model ID.
 *
 * @param handle Voice agent handle
 * @return Model ID string (static, do not free) or NULL if not loaded
 */
RAC_API const char* rac_voice_agent_get_llm_model_id(rac_voice_agent_handle_t handle);

/**
 * @brief Get the currently loaded TTS voice ID.
 *
 * @param handle Voice agent handle
 * @return Voice ID string (static, do not free) or NULL if not loaded
 */
RAC_API const char* rac_voice_agent_get_tts_voice_id(rac_voice_agent_handle_t handle);

/**
 * @brief Initialize the voice agent with configuration.
 *
 * Mirrors Swift's VoiceAgentCapability.initialize(_:).
 * This method is smart about reusing already-loaded models.
 *
 * @param handle Voice agent handle
 * @param config Configuration (can be NULL for defaults)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_initialize(rac_voice_agent_handle_t handle,
                                                const rac_voice_agent_config_t* config);

/**
 * @brief Initialize using already-loaded models.
 *
 * Mirrors Swift's VoiceAgentCapability.initializeWithLoadedModels().
 * Verifies all required components are loaded and marks the voice agent as ready.
 *
 * @param handle Voice agent handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle);

/**
 * @brief Cleanup voice agent resources.
 *
 * Mirrors Swift's VoiceAgentCapability.cleanup().
 *
 * @param handle Voice agent handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle);

/**
 * @brief Check if voice agent is ready.
 *
 * Mirrors Swift's VoiceAgentCapability.isReady property.
 *
 * @param handle Voice agent handle
 * @param out_is_ready Output: RAC_TRUE if ready
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle,
                                              rac_bool_t* out_is_ready);

// =============================================================================
// VOICE PROCESSING API
// =============================================================================

/**
 * @brief Process a complete voice turn: audio → transcription → LLM response → synthesized speech.
 *
 * Mirrors Swift's VoiceAgentCapability.processVoiceTurn(_:).
 *
 * @param handle Voice agent handle
 * @param audio_data Audio data from user
 * @param audio_size Size of audio data in bytes
 * @param out_result Output: Voice agent result (caller owns memory, must free with
 * rac_voice_agent_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_process_voice_turn(rac_voice_agent_handle_t handle,
                                                        const void* audio_data, size_t audio_size,
                                                        rac_voice_agent_result_t* out_result);

/**
 * @brief Process audio with streaming events.
 *
 * Mirrors Swift's VoiceAgentCapability.processStream(_:).
 * Events are delivered via the callback as processing progresses.
 *
 * @param handle Voice agent handle
 * @param audio_data Audio data from user
 * @param audio_size Size of audio data in bytes
 * @param callback Event callback function
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_process_stream(rac_voice_agent_handle_t handle,
                                                    const void* audio_data, size_t audio_size,
                                                    rac_voice_agent_event_callback_fn callback,
                                                    void* user_data);

// =============================================================================
// INDIVIDUAL COMPONENT ACCESS API
// =============================================================================

/**
 * @brief Transcribe audio only (without LLM/TTS).
 *
 * Mirrors Swift's VoiceAgentCapability.transcribe(_:).
 *
 * @param handle Voice agent handle
 * @param audio_data Audio data
 * @param audio_size Size of audio data in bytes
 * @param out_transcription Output: Transcribed text (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_transcribe(rac_voice_agent_handle_t handle,
                                                const void* audio_data, size_t audio_size,
                                                char** out_transcription);

/**
 * @brief Generate LLM response only.
 *
 * Mirrors Swift's VoiceAgentCapability.generateResponse(_:).
 *
 * @param handle Voice agent handle
 * @param prompt Input prompt
 * @param out_response Output: Generated response (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_generate_response(rac_voice_agent_handle_t handle,
                                                       const char* prompt, char** out_response);

/**
 * @brief Synthesize speech only.
 *
 * Mirrors Swift's VoiceAgentCapability.synthesizeSpeech(_:).
 *
 * @param handle Voice agent handle
 * @param text Text to synthesize
 * @param out_audio Output: Synthesized audio data (owned, must be freed with rac_free)
 * @param out_audio_size Output: Size of audio data in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_synthesize_speech(rac_voice_agent_handle_t handle,
                                                       const char* text, void** out_audio,
                                                       size_t* out_audio_size);

/**
 * @brief Check if VAD detects speech.
 *
 * Mirrors Swift's VoiceAgentCapability.detectSpeech(_:).
 *
 * @param handle Voice agent handle
 * @param samples Audio samples (float32)
 * @param sample_count Number of samples
 * @param out_speech_detected Output: RAC_TRUE if speech detected
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_detect_speech(rac_voice_agent_handle_t handle,
                                                   const float* samples, size_t sample_count,
                                                   rac_bool_t* out_speech_detected);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free a voice agent result.
 *
 * @param result Result to free
 */
RAC_API void rac_voice_agent_result_free(rac_voice_agent_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VOICE_AGENT_H */
