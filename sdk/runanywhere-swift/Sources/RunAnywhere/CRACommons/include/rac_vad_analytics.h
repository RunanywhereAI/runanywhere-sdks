/**
 * @file rac_vad_analytics.h
 * @brief VAD analytics service - 1:1 port of VADAnalyticsService.swift
 *
 * Tracks VAD operations and metrics.
 *
 * Swift Source: Sources/RunAnywhere/Features/VAD/Analytics/VADAnalyticsService.swift
 */

#ifndef RAC_VAD_ANALYTICS_H
#define RAC_VAD_ANALYTICS_H

#include "rac_types.h"
#include "rac_vad_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle for VAD analytics service
 */
typedef struct rac_vad_analytics_s* rac_vad_analytics_handle_t;

/**
 * @brief VAD metrics structure
 * Mirrors Swift's VADMetrics struct
 */
typedef struct rac_vad_metrics {
    /** Total number of events tracked */
    int32_t total_events;

    /** Start time (milliseconds since epoch) */
    int64_t start_time_ms;

    /** Last event time (milliseconds since epoch, 0 if no events) */
    int64_t last_event_time_ms;

    /** Total number of speech segments detected */
    int32_t total_speech_segments;

    /** Total speech duration in milliseconds */
    double total_speech_duration_ms;

    /** Average speech duration in milliseconds (-1 if no segments) */
    double average_speech_duration_ms;

    /** Current framework being used */
    rac_inference_framework_t framework;
} rac_vad_metrics_t;

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create a VAD analytics service instance
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_create(rac_vad_analytics_handle_t* out_handle);

/**
 * @brief Destroy a VAD analytics service instance
 *
 * @param handle Handle to destroy
 */
RAC_API void rac_vad_analytics_destroy(rac_vad_analytics_handle_t handle);

// =============================================================================
// LIFECYCLE TRACKING
// =============================================================================

/**
 * @brief Track VAD initialization
 *
 * @param handle Analytics service handle
 * @param framework The inference framework being used
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_initialized(rac_vad_analytics_handle_t handle,
                                                         rac_inference_framework_t framework);

/**
 * @brief Track VAD initialization failure
 *
 * @param handle Analytics service handle
 * @param error_code Error code
 * @param error_message Error message
 * @param framework The inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_initialization_failed(
    rac_vad_analytics_handle_t handle, rac_result_t error_code, const char* error_message,
    rac_inference_framework_t framework);

/**
 * @brief Track VAD cleanup
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_cleaned_up(rac_vad_analytics_handle_t handle);

// =============================================================================
// DETECTION TRACKING
// =============================================================================

/**
 * @brief Track VAD started
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_started(rac_vad_analytics_handle_t handle);

/**
 * @brief Track VAD stopped
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_stopped(rac_vad_analytics_handle_t handle);

/**
 * @brief Track speech detected (start of speech/voice activity)
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_speech_start(rac_vad_analytics_handle_t handle);

/**
 * @brief Track speech ended (silence detected after speech)
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_speech_end(rac_vad_analytics_handle_t handle);

/**
 * @brief Track VAD paused
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_paused(rac_vad_analytics_handle_t handle);

/**
 * @brief Track VAD resumed
 *
 * @param handle Analytics service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_resumed(rac_vad_analytics_handle_t handle);

// =============================================================================
// MODEL LIFECYCLE (for model-based VAD)
// =============================================================================

/**
 * @brief Track model load started
 *
 * @param handle Analytics service handle
 * @param model_id The model identifier
 * @param model_size_bytes Size of the model in bytes
 * @param framework The inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_model_load_started(
    rac_vad_analytics_handle_t handle, const char* model_id, int64_t model_size_bytes,
    rac_inference_framework_t framework);

/**
 * @brief Track model load completed
 *
 * @param handle Analytics service handle
 * @param model_id The model identifier
 * @param duration_ms Time taken to load in milliseconds
 * @param model_size_bytes Size of the model in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_model_load_completed(rac_vad_analytics_handle_t handle,
                                                                  const char* model_id,
                                                                  double duration_ms,
                                                                  int64_t model_size_bytes);

/**
 * @brief Track model load failed
 *
 * @param handle Analytics service handle
 * @param model_id The model identifier
 * @param error_code Error code
 * @param error_message Error message
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_model_load_failed(rac_vad_analytics_handle_t handle,
                                                               const char* model_id,
                                                               rac_result_t error_code,
                                                               const char* error_message);

/**
 * @brief Track model unloaded
 *
 * @param handle Analytics service handle
 * @param model_id The model identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_track_model_unloaded(rac_vad_analytics_handle_t handle,
                                                            const char* model_id);

// =============================================================================
// METRICS
// =============================================================================

/**
 * @brief Get current analytics metrics
 *
 * @param handle Analytics service handle
 * @param out_metrics Output: Metrics structure
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_analytics_get_metrics(rac_vad_analytics_handle_t handle,
                                                   rac_vad_metrics_t* out_metrics);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ANALYTICS_H */
