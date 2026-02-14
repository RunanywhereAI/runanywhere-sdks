/**
 * @file rac_wakeword_types.h
 * @brief RunAnywhere Commons - Wake Word Detection Types
 *
 * Type definitions for wake word detection feature.
 * Follows the same patterns as VAD, STT, TTS, LLM types.
 */

#ifndef RAC_WAKEWORD_TYPES_H
#define RAC_WAKEWORD_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// WAKE WORD EVENT
// =============================================================================

/**
 * @brief Wake word detection event
 *
 * Emitted when a wake word is detected in the audio stream.
 */
typedef struct rac_wakeword_event {
    /** Index of detected wake word (0-based, matches load order) */
    int32_t keyword_index;

    /** Name of detected wake word (e.g., "hey jarvis") */
    const char* keyword_name;

    /** Model ID that detected the wake word */
    const char* model_id;

    /** Confidence score (0.0 - 1.0) */
    float confidence;

    /** Timestamp in milliseconds (relative to stream start) */
    int64_t timestamp_ms;

    /** Duration of the detected wake word in milliseconds */
    int32_t duration_ms;
} rac_wakeword_event_t;

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief Wake word detection configuration
 */
typedef struct rac_wakeword_config {
    /** Sample rate in Hz (default: 16000) */
    int32_t sample_rate;

    /** Detection threshold (0.0 - 1.0, default: 0.5) */
    float threshold;

    /** Number of inference threads (0 = auto) */
    int32_t num_threads;

    /** Frame length in milliseconds (default: 80 for openWakeWord) */
    int32_t frame_length_ms;

    /** Enable VAD pre-filtering to reduce false positives */
    rac_bool_t use_vad_filter;

    /** Minimum time between detections in milliseconds (debounce) */
    int32_t min_detection_interval_ms;

    /** Refractory period after detection in milliseconds */
    int32_t refractory_period_ms;
} rac_wakeword_config_t;

/**
 * @brief Default configuration
 */
static const rac_wakeword_config_t RAC_WAKEWORD_CONFIG_DEFAULT = {
    .sample_rate = 16000,
    .threshold = 0.5f,
    .num_threads = 1,
    .frame_length_ms = 80,
    .use_vad_filter = RAC_TRUE,
    .min_detection_interval_ms = 500,
    .refractory_period_ms = 2000
};

// =============================================================================
// MODEL INFO
// =============================================================================

/**
 * @brief Information about a loaded wake word model
 */
typedef struct rac_wakeword_model_info {
    /** Unique model identifier */
    const char* model_id;

    /** Human-readable wake word phrase (e.g., "Hey Jarvis") */
    const char* wake_word;

    /** Model file path */
    const char* model_path;

    /** Language code (e.g., "en") */
    const char* language;

    /** Whether model is currently loaded */
    rac_bool_t is_loaded;

    /** Model-specific threshold override (-1 to use global) */
    float threshold_override;
} rac_wakeword_model_info_t;

// =============================================================================
// SERVICE INFO
// =============================================================================

/**
 * @brief Wake word service status information
 */
typedef struct rac_wakeword_info {
    /** Whether service is initialized and ready */
    rac_bool_t is_ready;

    /** Whether actively listening for wake words */
    rac_bool_t is_listening;

    /** Whether VAD filtering is enabled */
    rac_bool_t vad_enabled;

    /** Number of loaded wake word models */
    int32_t num_models;

    /** Array of loaded model info (owned by service) */
    const rac_wakeword_model_info_t* models;

    /** Total detections since start */
    int64_t total_detections;

    /** Current sample rate */
    int32_t sample_rate;

    /** Current threshold */
    float threshold;
} rac_wakeword_info_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief Wake word detection callback
 *
 * Called when a wake word is detected. The event data is valid only
 * for the duration of the callback.
 *
 * @param event Detection event (valid only during callback)
 * @param user_data User context passed to rac_wakeword_set_callback
 */
typedef void (*rac_wakeword_callback_fn)(const rac_wakeword_event_t* event,
                                          void* user_data);

/**
 * @brief VAD state callback (for debugging/visualization)
 *
 * @param is_speech Whether speech is currently detected
 * @param confidence VAD confidence (0.0 - 1.0)
 * @param user_data User context
 */
typedef void (*rac_wakeword_vad_callback_fn)(rac_bool_t is_speech,
                                              float confidence,
                                              void* user_data);

// =============================================================================
// RESULT TYPES
// =============================================================================

/**
 * @brief Result of processing a single audio frame
 */
typedef struct rac_wakeword_frame_result {
    /** Whether any wake word was detected */
    rac_bool_t detected;

    /** Index of detected keyword (-1 if none) */
    int32_t keyword_index;

    /** Detection confidence (0.0 - 1.0) */
    float confidence;

    /** VAD speech probability (0.0 - 1.0) */
    float vad_probability;

    /** Whether VAD detected speech */
    rac_bool_t vad_is_speech;
} rac_wakeword_frame_result_t;

// =============================================================================
// ERROR CODES
// =============================================================================

/** Wake word specific error codes (range: -850 to -860, per rac_error.h convention) */
#define RAC_ERROR_WAKEWORD_BASE               ((rac_result_t)-850)
#define RAC_ERROR_WAKEWORD_NOT_INITIALIZED    ((rac_result_t)-851)
#define RAC_ERROR_WAKEWORD_MODEL_NOT_FOUND    ((rac_result_t)-852)
#define RAC_ERROR_WAKEWORD_MODEL_LOAD_FAILED  ((rac_result_t)-853)
#define RAC_ERROR_WAKEWORD_INVALID_AUDIO      ((rac_result_t)-854)
#define RAC_ERROR_WAKEWORD_MAX_MODELS         ((rac_result_t)-855)
#define RAC_ERROR_WAKEWORD_ALREADY_LISTENING  ((rac_result_t)-856)
#define RAC_ERROR_WAKEWORD_NOT_LISTENING      ((rac_result_t)-857)

/** Maximum number of wake word models that can be loaded simultaneously */
#define RAC_WAKEWORD_MAX_MODELS 8

#ifdef __cplusplus
}
#endif

#endif /* RAC_WAKEWORD_TYPES_H */
