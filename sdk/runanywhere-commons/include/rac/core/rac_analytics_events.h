/**
 * @file rac_events.h
 * @brief RunAnywhere Commons - Cross-Platform Event System
 *
 * C++ is the canonical source of truth for all analytics events.
 * Platform SDKs (Swift, Kotlin, Flutter) register callbacks to receive
 * these events and forward them to their native event systems.
 *
 * Usage:
 * 1. Platform SDK registers callback via rac_events_set_callback()
 * 2. C++ components emit events via rac_event_emit()
 * 3. Platform SDK receives events in callback and converts to native events
 */

#ifndef RAC_ANALYTICS_EVENTS_H
#define RAC_ANALYTICS_EVENTS_H

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EVENT TYPES
// =============================================================================

/**
 * @brief Event type enumeration
 */
typedef enum rac_event_type {
    // LLM Events
    RAC_EVENT_LLM_MODEL_LOAD_STARTED = 100,
    RAC_EVENT_LLM_MODEL_LOAD_COMPLETED = 101,
    RAC_EVENT_LLM_MODEL_LOAD_FAILED = 102,
    RAC_EVENT_LLM_MODEL_UNLOADED = 103,
    RAC_EVENT_LLM_GENERATION_STARTED = 110,
    RAC_EVENT_LLM_GENERATION_COMPLETED = 111,
    RAC_EVENT_LLM_GENERATION_FAILED = 112,
    RAC_EVENT_LLM_FIRST_TOKEN = 113,
    RAC_EVENT_LLM_STREAMING_UPDATE = 114,

    // STT Events
    RAC_EVENT_STT_MODEL_LOAD_STARTED = 200,
    RAC_EVENT_STT_MODEL_LOAD_COMPLETED = 201,
    RAC_EVENT_STT_MODEL_LOAD_FAILED = 202,
    RAC_EVENT_STT_MODEL_UNLOADED = 203,
    RAC_EVENT_STT_TRANSCRIPTION_STARTED = 210,
    RAC_EVENT_STT_TRANSCRIPTION_COMPLETED = 211,
    RAC_EVENT_STT_TRANSCRIPTION_FAILED = 212,
    RAC_EVENT_STT_PARTIAL_TRANSCRIPT = 213,

    // TTS Events
    RAC_EVENT_TTS_VOICE_LOAD_STARTED = 300,
    RAC_EVENT_TTS_VOICE_LOAD_COMPLETED = 301,
    RAC_EVENT_TTS_VOICE_LOAD_FAILED = 302,
    RAC_EVENT_TTS_VOICE_UNLOADED = 303,
    RAC_EVENT_TTS_SYNTHESIS_STARTED = 310,
    RAC_EVENT_TTS_SYNTHESIS_COMPLETED = 311,
    RAC_EVENT_TTS_SYNTHESIS_FAILED = 312,
    RAC_EVENT_TTS_SYNTHESIS_CHUNK = 313,

    // VAD Events
    RAC_EVENT_VAD_STARTED = 400,
    RAC_EVENT_VAD_STOPPED = 401,
    RAC_EVENT_VAD_SPEECH_STARTED = 402,
    RAC_EVENT_VAD_SPEECH_ENDED = 403,
    RAC_EVENT_VAD_PAUSED = 404,
    RAC_EVENT_VAD_RESUMED = 405,

    // VoiceAgent Events
    RAC_EVENT_VOICE_AGENT_TURN_STARTED = 500,
    RAC_EVENT_VOICE_AGENT_TURN_COMPLETED = 501,
    RAC_EVENT_VOICE_AGENT_TURN_FAILED = 502,
} rac_event_type_t;

// =============================================================================
// EVENT DATA STRUCTURES
// =============================================================================

/**
 * @brief LLM generation analytics event data
 * Used for: GENERATION_STARTED, GENERATION_COMPLETED, GENERATION_FAILED
 */
typedef struct rac_analytics_llm_generation {
    /** Unique generation identifier */
    const char* generation_id;
    /** Model ID used for generation */
    const char* model_id;
    /** Number of input/prompt tokens */
    int32_t input_tokens;
    /** Number of output/completion tokens */
    int32_t output_tokens;
    /** Total duration in milliseconds */
    double duration_ms;
    /** Tokens generated per second */
    double tokens_per_second;
    /** Whether this was a streaming generation */
    rac_bool_t is_streaming;
    /** Time to first token in ms (0 if not streaming or not yet received) */
    double time_to_first_token_ms;
    /** Inference framework used */
    rac_inference_framework_t framework;
    /** Generation temperature (0 if not set) */
    float temperature;
    /** Max tokens setting (0 if not set) */
    int32_t max_tokens;
    /** Context length (0 if not set) */
    int32_t context_length;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_llm_generation_t;

/**
 * @brief LLM model load analytics event data
 * Used for: MODEL_LOAD_STARTED, MODEL_LOAD_COMPLETED, MODEL_LOAD_FAILED
 */
typedef struct rac_analytics_llm_model {
    /** Model ID */
    const char* model_id;
    /** Model size in bytes (0 if unknown) */
    int64_t model_size_bytes;
    /** Load duration in milliseconds (for completed event) */
    double duration_ms;
    /** Inference framework */
    rac_inference_framework_t framework;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_llm_model_t;

/**
 * @brief STT transcription event data
 * Used for: TRANSCRIPTION_STARTED, TRANSCRIPTION_COMPLETED, TRANSCRIPTION_FAILED
 */
typedef struct rac_analytics_stt_transcription {
    /** Unique transcription identifier */
    const char* transcription_id;
    /** Model ID used */
    const char* model_id;
    /** Transcribed text (for completed event) */
    const char* text;
    /** Confidence score (0.0 - 1.0) */
    float confidence;
    /** Processing duration in milliseconds */
    double duration_ms;
    /** Audio length in milliseconds */
    double audio_length_ms;
    /** Audio size in bytes */
    int32_t audio_size_bytes;
    /** Word count in result */
    int32_t word_count;
    /** Real-time factor (audio_length / processing_time) */
    double real_time_factor;
    /** Language code */
    const char* language;
    /** Sample rate */
    int32_t sample_rate;
    /** Whether streaming transcription */
    rac_bool_t is_streaming;
    /** Inference framework */
    rac_inference_framework_t framework;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_stt_transcription_t;

/**
 * @brief TTS synthesis event data
 * Used for: SYNTHESIS_STARTED, SYNTHESIS_COMPLETED, SYNTHESIS_FAILED
 */
typedef struct rac_analytics_tts_synthesis {
    /** Unique synthesis identifier */
    const char* synthesis_id;
    /** Voice/Model ID used */
    const char* model_id;
    /** Character count of input text */
    int32_t character_count;
    /** Audio duration in milliseconds */
    double audio_duration_ms;
    /** Audio size in bytes */
    int32_t audio_size_bytes;
    /** Processing duration in milliseconds */
    double processing_duration_ms;
    /** Characters processed per second */
    double characters_per_second;
    /** Sample rate */
    int32_t sample_rate;
    /** Inference framework */
    rac_inference_framework_t framework;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_tts_synthesis_t;

/**
 * @brief VAD event data
 * Used for: VAD_STARTED, VAD_STOPPED, VAD_SPEECH_STARTED, VAD_SPEECH_ENDED
 */
typedef struct rac_analytics_vad {
    /** Speech duration in milliseconds (for SPEECH_ENDED) */
    double speech_duration_ms;
    /** Energy level (for speech events) */
    float energy_level;
} rac_analytics_vad_t;

/**
 * @brief Union of all event data types
 */
typedef struct rac_analytics_event_data {
    rac_event_type_t type;
    union {
        rac_analytics_llm_generation_t llm_generation;
        rac_analytics_llm_model_t llm_model;
        rac_analytics_stt_transcription_t stt_transcription;
        rac_analytics_tts_synthesis_t tts_synthesis;
        rac_analytics_vad_t vad;
    } data;
} rac_analytics_event_data_t;

// =============================================================================
// EVENT CALLBACK API
// =============================================================================

/**
 * @brief Event callback function type
 *
 * Platform SDKs implement this callback to receive events from C++.
 *
 * @param type Event type
 * @param data Event data (lifetime: only valid during callback)
 * @param user_data User data provided during registration
 */
typedef void (*rac_analytics_callback_fn)(rac_event_type_t type,
                                          const rac_analytics_event_data_t* data, void* user_data);

/**
 * @brief Register analytics event callback
 *
 * Called by platform SDKs at initialization to receive analytics events.
 * Only one callback can be registered at a time.
 *
 * @param callback Callback function (NULL to unregister)
 * @param user_data User data passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_analytics_events_set_callback(rac_analytics_callback_fn callback,
                                                       void* user_data);

/**
 * @brief Emit an analytics event
 *
 * Called internally by C++ components to emit analytics events.
 * If no callback is registered, event is silently discarded.
 *
 * @param type Event type
 * @param data Event data
 */
RAC_API void rac_analytics_event_emit(rac_event_type_t type,
                                      const rac_analytics_event_data_t* data);

/**
 * @brief Check if analytics event callback is registered
 *
 * @return RAC_TRUE if callback is registered, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_analytics_events_has_callback(void);

// =============================================================================
// DEFAULT EVENT DATA
// =============================================================================

/** Default LLM generation event */
static const rac_analytics_llm_generation_t RAC_ANALYTICS_LLM_GENERATION_DEFAULT = {
    .generation_id = RAC_NULL,
    .model_id = RAC_NULL,
    .input_tokens = 0,
    .output_tokens = 0,
    .duration_ms = 0.0,
    .tokens_per_second = 0.0,
    .is_streaming = RAC_FALSE,
    .time_to_first_token_ms = 0.0,
    .framework = RAC_FRAMEWORK_UNKNOWN,
    .temperature = 0.0f,
    .max_tokens = 0,
    .context_length = 0,
    .error_code = RAC_SUCCESS,
    .error_message = RAC_NULL};

/** Default STT transcription event */
static const rac_analytics_stt_transcription_t RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT = {
    .transcription_id = RAC_NULL,
    .model_id = RAC_NULL,
    .text = RAC_NULL,
    .confidence = 0.0f,
    .duration_ms = 0.0,
    .audio_length_ms = 0.0,
    .audio_size_bytes = 0,
    .word_count = 0,
    .real_time_factor = 0.0,
    .language = RAC_NULL,
    .sample_rate = 0,
    .is_streaming = RAC_FALSE,
    .framework = RAC_FRAMEWORK_UNKNOWN,
    .error_code = RAC_SUCCESS,
    .error_message = RAC_NULL};

/** Default TTS synthesis event */
static const rac_analytics_tts_synthesis_t RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT = {
    .synthesis_id = RAC_NULL,
    .model_id = RAC_NULL,
    .character_count = 0,
    .audio_duration_ms = 0.0,
    .audio_size_bytes = 0,
    .processing_duration_ms = 0.0,
    .characters_per_second = 0.0,
    .sample_rate = 0,
    .framework = RAC_FRAMEWORK_UNKNOWN,
    .error_code = RAC_SUCCESS,
    .error_message = RAC_NULL};

/** Default VAD event */
static const rac_analytics_vad_t RAC_ANALYTICS_VAD_DEFAULT = {.speech_duration_ms = 0.0,
                                                              .energy_level = 0.0f};

#ifdef __cplusplus
}
#endif

#endif /* RAC_ANALYTICS_EVENTS_H */
