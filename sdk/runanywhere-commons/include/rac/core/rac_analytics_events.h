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
// EVENT DESTINATION
// =============================================================================

// Include the event publishing header for destination types
#include "rac/infrastructure/events/rac_events.h"

// Alias the existing enum values for convenience in analytics context
#define RAC_EVENT_DEST_PUBLIC_ONLY RAC_EVENT_DESTINATION_PUBLIC_ONLY
#define RAC_EVENT_DEST_TELEMETRY_ONLY RAC_EVENT_DESTINATION_ANALYTICS_ONLY
#define RAC_EVENT_DEST_ALL RAC_EVENT_DESTINATION_ALL

// =============================================================================
// EVENT TYPES
// =============================================================================

/**
 * @brief Event type enumeration
 */
typedef enum rac_event_type {
    // LLM Events (100-199)
    RAC_EVENT_LLM_MODEL_LOAD_STARTED = 100,
    RAC_EVENT_LLM_MODEL_LOAD_COMPLETED = 101,
    RAC_EVENT_LLM_MODEL_LOAD_FAILED = 102,
    RAC_EVENT_LLM_MODEL_UNLOADED = 103,
    RAC_EVENT_LLM_GENERATION_STARTED = 110,
    RAC_EVENT_LLM_GENERATION_COMPLETED = 111,
    RAC_EVENT_LLM_GENERATION_FAILED = 112,
    RAC_EVENT_LLM_FIRST_TOKEN = 113,
    RAC_EVENT_LLM_STREAMING_UPDATE = 114,

    // STT Events (200-299)
    RAC_EVENT_STT_MODEL_LOAD_STARTED = 200,
    RAC_EVENT_STT_MODEL_LOAD_COMPLETED = 201,
    RAC_EVENT_STT_MODEL_LOAD_FAILED = 202,
    RAC_EVENT_STT_MODEL_UNLOADED = 203,
    RAC_EVENT_STT_TRANSCRIPTION_STARTED = 210,
    RAC_EVENT_STT_TRANSCRIPTION_COMPLETED = 211,
    RAC_EVENT_STT_TRANSCRIPTION_FAILED = 212,
    RAC_EVENT_STT_PARTIAL_TRANSCRIPT = 213,

    // TTS Events (300-399)
    RAC_EVENT_TTS_VOICE_LOAD_STARTED = 300,
    RAC_EVENT_TTS_VOICE_LOAD_COMPLETED = 301,
    RAC_EVENT_TTS_VOICE_LOAD_FAILED = 302,
    RAC_EVENT_TTS_VOICE_UNLOADED = 303,
    RAC_EVENT_TTS_SYNTHESIS_STARTED = 310,
    RAC_EVENT_TTS_SYNTHESIS_COMPLETED = 311,
    RAC_EVENT_TTS_SYNTHESIS_FAILED = 312,
    RAC_EVENT_TTS_SYNTHESIS_CHUNK = 313,

    // VAD Events (400-499)
    RAC_EVENT_VAD_STARTED = 400,
    RAC_EVENT_VAD_STOPPED = 401,
    RAC_EVENT_VAD_SPEECH_STARTED = 402,
    RAC_EVENT_VAD_SPEECH_ENDED = 403,
    RAC_EVENT_VAD_PAUSED = 404,
    RAC_EVENT_VAD_RESUMED = 405,

    // VoiceAgent Events (500-599)
    RAC_EVENT_VOICE_AGENT_TURN_STARTED = 500,
    RAC_EVENT_VOICE_AGENT_TURN_COMPLETED = 501,
    RAC_EVENT_VOICE_AGENT_TURN_FAILED = 502,
    // Voice Agent Component State Events
    RAC_EVENT_VOICE_AGENT_STT_STATE_CHANGED = 510,
    RAC_EVENT_VOICE_AGENT_LLM_STATE_CHANGED = 511,
    RAC_EVENT_VOICE_AGENT_TTS_STATE_CHANGED = 512,
    RAC_EVENT_VOICE_AGENT_ALL_READY = 513,

    // SDK Lifecycle Events (600-699)
    RAC_EVENT_SDK_INIT_STARTED = 600,
    RAC_EVENT_SDK_INIT_COMPLETED = 601,
    RAC_EVENT_SDK_INIT_FAILED = 602,
    RAC_EVENT_SDK_MODELS_LOADED = 603,

    // Model Download Events (700-719)
    RAC_EVENT_MODEL_DOWNLOAD_STARTED = 700,
    RAC_EVENT_MODEL_DOWNLOAD_PROGRESS = 701,
    RAC_EVENT_MODEL_DOWNLOAD_COMPLETED = 702,
    RAC_EVENT_MODEL_DOWNLOAD_FAILED = 703,
    RAC_EVENT_MODEL_DOWNLOAD_CANCELLED = 704,

    // Model Extraction Events (710-719)
    RAC_EVENT_MODEL_EXTRACTION_STARTED = 710,
    RAC_EVENT_MODEL_EXTRACTION_PROGRESS = 711,
    RAC_EVENT_MODEL_EXTRACTION_COMPLETED = 712,
    RAC_EVENT_MODEL_EXTRACTION_FAILED = 713,

    // Model Deletion Events (720-729)
    RAC_EVENT_MODEL_DELETED = 720,

    // Storage Events (800-899)
    RAC_EVENT_STORAGE_CACHE_CLEARED = 800,
    RAC_EVENT_STORAGE_CACHE_CLEAR_FAILED = 801,
    RAC_EVENT_STORAGE_TEMP_CLEANED = 802,

    // Device Events (900-999)
    RAC_EVENT_DEVICE_REGISTERED = 900,
    RAC_EVENT_DEVICE_REGISTRATION_FAILED = 901,

    // Network Events (1000-1099)
    RAC_EVENT_NETWORK_CONNECTIVITY_CHANGED = 1000,

    // Error Events (1100-1199)
    RAC_EVENT_SDK_ERROR = 1100,

    // Framework Events (1200-1299)
    RAC_EVENT_FRAMEWORK_MODELS_REQUESTED = 1200,
    RAC_EVENT_FRAMEWORK_MODELS_RETRIEVED = 1201,
} rac_event_type_t;

/**
 * @brief Get the destination for an event type
 *
 * @param type Event type
 * @return Event destination
 */
RAC_API rac_event_destination_t rac_event_get_destination(rac_event_type_t type);

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
    /** Human-readable model name */
    const char* model_name;
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
    /** Human-readable model name */
    const char* model_name;
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
    /** Human-readable model name */
    const char* model_name;
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
    /** Human-readable voice/model name */
    const char* model_name;
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
 * @brief Model download event data
 * Used for: MODEL_DOWNLOAD_*, MODEL_EXTRACTION_*, MODEL_DELETED
 */
typedef struct rac_analytics_model_download {
    /** Model identifier */
    const char* model_id;
    /** Download progress (0.0 - 100.0) */
    double progress;
    /** Bytes downloaded so far */
    int64_t bytes_downloaded;
    /** Total bytes to download */
    int64_t total_bytes;
    /** Duration in milliseconds */
    double duration_ms;
    /** Final size in bytes (for completed event) */
    int64_t size_bytes;
    /** Archive type (e.g., "zip", "tar.gz", "none") */
    const char* archive_type;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_model_download_t;

/**
 * @brief SDK lifecycle event data
 * Used for: SDK_INIT_*, SDK_MODELS_LOADED
 */
typedef struct rac_analytics_sdk_lifecycle {
    /** Duration in milliseconds */
    double duration_ms;
    /** Count (e.g., number of models loaded) */
    int32_t count;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_sdk_lifecycle_t;

/**
 * @brief Storage event data
 * Used for: STORAGE_CACHE_CLEARED, STORAGE_TEMP_CLEANED
 */
typedef struct rac_analytics_storage {
    /** Bytes freed */
    int64_t freed_bytes;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_storage_t;

/**
 * @brief Device event data
 * Used for: DEVICE_REGISTERED, DEVICE_REGISTRATION_FAILED
 */
typedef struct rac_analytics_device {
    /** Device identifier */
    const char* device_id;
    /** Error code (RAC_SUCCESS if no error) */
    rac_result_t error_code;
    /** Error message (NULL if no error) */
    const char* error_message;
} rac_analytics_device_t;

/**
 * @brief Network event data
 * Used for: NETWORK_CONNECTIVITY_CHANGED
 */
typedef struct rac_analytics_network {
    /** Whether the device is online */
    rac_bool_t is_online;
} rac_analytics_network_t;

/**
 * @brief SDK error event data
 * Used for: SDK_ERROR
 */
typedef struct rac_analytics_sdk_error {
    /** Error code */
    rac_result_t error_code;
    /** Error message */
    const char* error_message;
    /** Operation that failed */
    const char* operation;
    /** Additional context */
    const char* context;
} rac_analytics_sdk_error_t;

/**
 * @brief Voice agent component state
 * Used for: VOICE_AGENT_*_STATE_CHANGED events
 */
typedef enum rac_voice_agent_component_state {
    RAC_VOICE_AGENT_STATE_NOT_LOADED = 0,
    RAC_VOICE_AGENT_STATE_LOADING = 1,
    RAC_VOICE_AGENT_STATE_LOADED = 2,
    RAC_VOICE_AGENT_STATE_ERROR = 3,
} rac_voice_agent_component_state_t;

/**
 * @brief Voice agent state change event data
 * Used for: VOICE_AGENT_STT_STATE_CHANGED, VOICE_AGENT_LLM_STATE_CHANGED,
 *           VOICE_AGENT_TTS_STATE_CHANGED, VOICE_AGENT_ALL_READY
 */
typedef struct rac_analytics_voice_agent_state {
    /** Component name: "stt", "llm", "tts", or "all" */
    const char* component;
    /** New state */
    rac_voice_agent_component_state_t state;
    /** Model ID (if loaded) */
    const char* model_id;
    /** Error message (if state is ERROR) */
    const char* error_message;
} rac_analytics_voice_agent_state_t;

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
        rac_analytics_model_download_t model_download;
        rac_analytics_sdk_lifecycle_t sdk_lifecycle;
        rac_analytics_storage_t storage;
        rac_analytics_device_t device;
        rac_analytics_network_t network;
        rac_analytics_sdk_error_t sdk_error;
        rac_analytics_voice_agent_state_t voice_agent_state;
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
// PUBLIC EVENT CALLBACK API
// =============================================================================

/**
 * @brief Public event callback function type
 *
 * Platform SDKs implement this callback to receive public events from C++.
 * Public events are intended for app developers (UI updates, user feedback).
 *
 * @param type Event type
 * @param data Event data (lifetime: only valid during callback)
 * @param user_data User data provided during registration
 */
typedef void (*rac_public_event_callback_fn)(rac_event_type_t type,
                                             const rac_analytics_event_data_t* data,
                                             void* user_data);

/**
 * @brief Register public event callback
 *
 * Called by platform SDKs to receive public events (for app developers).
 * Events are routed based on their destination:
 * - PUBLIC_ONLY: Only sent to this callback
 * - ALL: Sent to both this callback and telemetry
 *
 * @param callback Callback function (NULL to unregister)
 * @param user_data User data passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_analytics_events_set_public_callback(rac_public_event_callback_fn callback,
                                                              void* user_data);

/**
 * @brief Check if public event callback is registered
 *
 * @return RAC_TRUE if callback is registered, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_analytics_events_has_public_callback(void);

// =============================================================================
// PLATFORM EMIT HELPERS
// =============================================================================
//
// C-linkage convenience functions for platform SDKs (Web, Kotlin) that need to
// emit analytics events from outside the C++ component layer.  Each function
// accepts individual parameters, constructs the C struct internally, and calls
// rac_analytics_event_emit().  On the Web SDK these are called via Emscripten
// ccall() which handles string marshalling automatically.

RAC_API void rac_analytics_emit_stt_model_load_completed(
    const char* model_id, const char* model_name, double duration_ms, int32_t framework);

RAC_API void rac_analytics_emit_stt_model_load_failed(
    const char* model_id, int32_t error_code, const char* error_message);

RAC_API void rac_analytics_emit_stt_transcription_completed(
    const char* transcription_id, const char* model_id, const char* text,
    float confidence, double duration_ms, double audio_length_ms,
    int32_t audio_size_bytes, int32_t word_count, double real_time_factor,
    const char* language, int32_t sample_rate, int32_t framework);

RAC_API void rac_analytics_emit_stt_transcription_failed(
    const char* transcription_id, const char* model_id,
    int32_t error_code, const char* error_message);

RAC_API void rac_analytics_emit_tts_voice_load_completed(
    const char* model_id, const char* model_name, double duration_ms, int32_t framework);

RAC_API void rac_analytics_emit_tts_voice_load_failed(
    const char* model_id, int32_t error_code, const char* error_message);

RAC_API void rac_analytics_emit_tts_synthesis_completed(
    const char* synthesis_id, const char* model_id,
    int32_t character_count, double audio_duration_ms, int32_t audio_size_bytes,
    double processing_duration_ms, double characters_per_second,
    int32_t sample_rate, int32_t framework);

RAC_API void rac_analytics_emit_tts_synthesis_failed(
    const char* synthesis_id, const char* model_id,
    int32_t error_code, const char* error_message);

RAC_API void rac_analytics_emit_vad_speech_started(void);

RAC_API void rac_analytics_emit_vad_speech_ended(double speech_duration_ms, float energy_level);

RAC_API void rac_analytics_emit_model_download_started(const char* model_id);

RAC_API void rac_analytics_emit_model_download_completed(
    const char* model_id, int64_t file_size_bytes, double duration_ms);

RAC_API void rac_analytics_emit_model_download_failed(
    const char* model_id, const char* error_message);

// =============================================================================
// DEFAULT EVENT DATA
// =============================================================================

/** Default LLM generation event */
static const rac_analytics_llm_generation_t RAC_ANALYTICS_LLM_GENERATION_DEFAULT = {
    .generation_id = RAC_NULL,
    .model_id = RAC_NULL,
    .model_name = RAC_NULL,
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
    .model_name = RAC_NULL,
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
    .model_name = RAC_NULL,
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

/** Default model download event */
static const rac_analytics_model_download_t RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT = {
    .model_id = RAC_NULL,
    .progress = 0.0,
    .bytes_downloaded = 0,
    .total_bytes = 0,
    .duration_ms = 0.0,
    .size_bytes = 0,
    .archive_type = RAC_NULL,
    .error_code = RAC_SUCCESS,
    .error_message = RAC_NULL};

/** Default SDK lifecycle event */
static const rac_analytics_sdk_lifecycle_t RAC_ANALYTICS_SDK_LIFECYCLE_DEFAULT = {
    .duration_ms = 0.0, .count = 0, .error_code = RAC_SUCCESS, .error_message = RAC_NULL};

/** Default storage event */
static const rac_analytics_storage_t RAC_ANALYTICS_STORAGE_DEFAULT = {
    .freed_bytes = 0, .error_code = RAC_SUCCESS, .error_message = RAC_NULL};

/** Default device event */
static const rac_analytics_device_t RAC_ANALYTICS_DEVICE_DEFAULT = {
    .device_id = RAC_NULL, .error_code = RAC_SUCCESS, .error_message = RAC_NULL};

/** Default network event */
static const rac_analytics_network_t RAC_ANALYTICS_NETWORK_DEFAULT = {.is_online = RAC_FALSE};

/** Default SDK error event */
static const rac_analytics_sdk_error_t RAC_ANALYTICS_SDK_ERROR_DEFAULT = {.error_code = RAC_SUCCESS,
                                                                          .error_message = RAC_NULL,
                                                                          .operation = RAC_NULL,
                                                                          .context = RAC_NULL};

#ifdef __cplusplus
}
#endif

#endif /* RAC_ANALYTICS_EVENTS_H */
