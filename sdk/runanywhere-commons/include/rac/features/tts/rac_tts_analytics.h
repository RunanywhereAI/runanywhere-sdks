/**
 * @file rac_tts_analytics.h
 * @brief TTS analytics service - 1:1 port of TTSAnalyticsService.swift
 *
 * Tracks synthesis operations and metrics.
 * Lifecycle events are handled by the lifecycle manager.
 *
 * NOTE: Audio duration estimation assumes 16-bit PCM @ 22050Hz (standard for TTS).
 * Formula: audioDurationMs = (bytes / 2) / 22050 * 1000
 *
 * Swift Source: Sources/RunAnywhere/Features/TTS/Analytics/TTSAnalyticsService.swift
 */

#ifndef RAC_TTS_ANALYTICS_H
#define RAC_TTS_ANALYTICS_H

#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle for TTS analytics service
 */
typedef struct rac_tts_analytics_s* rac_tts_analytics_handle_t;

/**
 * @brief TTS metrics structure
 * Mirrors Swift's TTSMetrics struct
 */
typedef struct rac_tts_metrics {
    /** Total number of events tracked */
    int32_t total_events;

    /** Start time (milliseconds since epoch) */
    int64_t start_time_ms;

    /** Last event time (milliseconds since epoch, 0 if no events) */
    int64_t last_event_time_ms;

    /** Total number of syntheses */
    int32_t total_syntheses;

    /** Average synthesis speed (characters processed per second) */
    double average_characters_per_second;

    /** Average processing time in milliseconds */
    double average_processing_time_ms;

    /** Average audio duration in milliseconds */
    double average_audio_duration_ms;

    /** Total characters processed across all syntheses */
    int32_t total_characters_processed;

    /** Total audio size generated in bytes */
    int64_t total_audio_size_bytes;
} rac_tts_metrics_t;

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create a TTS analytics service instance
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_create(rac_tts_analytics_handle_t* out_handle);

/**
 * @brief Destroy a TTS analytics service instance
 *
 * @param handle Handle to destroy
 */
RAC_API void rac_tts_analytics_destroy(rac_tts_analytics_handle_t handle);

// =============================================================================
// SYNTHESIS TRACKING
// =============================================================================

/**
 * @brief Start tracking a synthesis
 *
 * @param handle Analytics service handle
 * @param text The text to synthesize
 * @param voice The voice ID being used
 * @param sample_rate Audio sample rate in Hz (default: 22050)
 * @param framework The inference framework being used
 * @param out_synthesis_id Output: Generated unique ID (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_start_synthesis(
    rac_tts_analytics_handle_t handle,
    const char* text,
    const char* voice,
    int32_t sample_rate,
    rac_inference_framework_t framework,
    char** out_synthesis_id
);

/**
 * @brief Track synthesis chunk (for streaming synthesis)
 *
 * @param handle Analytics service handle
 * @param synthesis_id The synthesis ID
 * @param chunk_size Size of the chunk in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_track_synthesis_chunk(
    rac_tts_analytics_handle_t handle,
    const char* synthesis_id,
    int32_t chunk_size
);

/**
 * @brief Complete a synthesis
 *
 * @param handle Analytics service handle
 * @param synthesis_id The synthesis ID
 * @param audio_duration_ms Duration of the generated audio in milliseconds
 * @param audio_size_bytes Size of the generated audio in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_complete_synthesis(
    rac_tts_analytics_handle_t handle,
    const char* synthesis_id,
    double audio_duration_ms,
    int32_t audio_size_bytes
);

/**
 * @brief Track synthesis failure
 *
 * @param handle Analytics service handle
 * @param synthesis_id The synthesis ID
 * @param error_code Error code
 * @param error_message Error message
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_track_synthesis_failed(
    rac_tts_analytics_handle_t handle,
    const char* synthesis_id,
    rac_result_t error_code,
    const char* error_message
);

/**
 * @brief Track an error during TTS operations
 *
 * @param handle Analytics service handle
 * @param error_code Error code
 * @param error_message Error message
 * @param operation Operation that failed
 * @param model_id Model ID (can be NULL)
 * @param synthesis_id Synthesis ID (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_analytics_track_error(
    rac_tts_analytics_handle_t handle,
    rac_result_t error_code,
    const char* error_message,
    const char* operation,
    const char* model_id,
    const char* synthesis_id
);

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
RAC_API rac_result_t rac_tts_analytics_get_metrics(
    rac_tts_analytics_handle_t handle,
    rac_tts_metrics_t* out_metrics
);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_ANALYTICS_H */
