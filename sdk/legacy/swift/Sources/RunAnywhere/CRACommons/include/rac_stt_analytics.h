/**
 * @file rac_stt_analytics.h
 * @brief STT analytics service - 1:1 port of STTAnalyticsService.swift
 *
 * Tracks transcription operations and metrics.
 * Lifecycle events are handled by the lifecycle manager.
 *
 * NOTE: Audio length estimation assumes 16-bit PCM @ 16kHz (standard for STT).
 * Formula: audioLengthMs = (bytes / 2) / 16000 * 1000
 *
 * NOTE: Real-Time Factor (RTF) will be 0 or undefined for streaming transcription
 * since audioLengthMs = 0 when audio is processed in chunks of unknown total length.
 *
 * Swift Source: Sources/RunAnywhere/Features/STT/Analytics/STTAnalyticsService.swift
 */

#ifndef RAC_STT_ANALYTICS_H
#define RAC_STT_ANALYTICS_H

#include "rac_types.h"
#include "rac_stt_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle for STT analytics service
 */
typedef struct rac_stt_analytics_s* rac_stt_analytics_handle_t;

/**
 * @brief STT metrics structure
 * Mirrors Swift's STTMetrics struct
 */
typedef struct rac_stt_metrics {
    /** Total number of events tracked */
    int32_t total_events;

    /** Start time (milliseconds since epoch) */
    int64_t start_time_ms;

    /** Last event time (milliseconds since epoch, 0 if no events) */
    int64_t last_event_time_ms;

    /** Total number of transcriptions */
    int32_t total_transcriptions;

    /** Average confidence score across all transcriptions (0.0 to 1.0) */
    float average_confidence;

    /** Average processing latency in milliseconds */
    double average_latency_ms;

    /** Average real-time factor (processing time / audio length) */
    double average_real_time_factor;

    /** Total audio processed in milliseconds */
    double total_audio_processed_ms;
} rac_stt_metrics_t;

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create an STT analytics service instance
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_create(rac_stt_analytics_handle_t* out_handle);

/**
 * @brief Destroy an STT analytics service instance
 *
 * @param handle Handle to destroy
 */
RAC_API void rac_stt_analytics_destroy(rac_stt_analytics_handle_t handle);

// =============================================================================
// TRANSCRIPTION TRACKING
// =============================================================================

/**
 * @brief Start tracking a transcription
 *
 * @param handle Analytics service handle
 * @param model_id The STT model identifier
 * @param audio_length_ms Duration of audio in milliseconds
 * @param audio_size_bytes Size of audio data in bytes
 * @param language Language code for transcription
 * @param is_streaming Whether this is a streaming transcription
 * @param sample_rate Audio sample rate in Hz (default: 16000)
 * @param framework The inference framework being used
 * @param out_transcription_id Output: Generated unique ID (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_start_transcription(
    rac_stt_analytics_handle_t handle, const char* model_id, double audio_length_ms,
    int32_t audio_size_bytes, const char* language, rac_bool_t is_streaming, int32_t sample_rate,
    rac_inference_framework_t framework, char** out_transcription_id);

/**
 * @brief Track partial transcript (for streaming transcription)
 *
 * @param handle Analytics service handle
 * @param text Partial transcript text
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_track_partial_transcript(rac_stt_analytics_handle_t handle,
                                                                const char* text);

/**
 * @brief Track final transcript (for streaming transcription)
 *
 * @param handle Analytics service handle
 * @param text Final transcript text
 * @param confidence Confidence score (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_track_final_transcript(rac_stt_analytics_handle_t handle,
                                                              const char* text, float confidence);

/**
 * @brief Complete a transcription
 *
 * @param handle Analytics service handle
 * @param transcription_id The transcription ID
 * @param text The transcribed text
 * @param confidence Confidence score (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_complete_transcription(rac_stt_analytics_handle_t handle,
                                                              const char* transcription_id,
                                                              const char* text, float confidence);

/**
 * @brief Track transcription failure
 *
 * @param handle Analytics service handle
 * @param transcription_id The transcription ID
 * @param error_code Error code
 * @param error_message Error message
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_track_transcription_failed(rac_stt_analytics_handle_t handle,
                                                                  const char* transcription_id,
                                                                  rac_result_t error_code,
                                                                  const char* error_message);

/**
 * @brief Track language detection
 *
 * @param handle Analytics service handle
 * @param language Detected language code
 * @param confidence Detection confidence (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_track_language_detection(rac_stt_analytics_handle_t handle,
                                                                const char* language,
                                                                float confidence);

/**
 * @brief Track an error during STT operations
 *
 * @param handle Analytics service handle
 * @param error_code Error code
 * @param error_message Error message
 * @param operation Operation that failed
 * @param model_id Model ID (can be NULL)
 * @param transcription_id Transcription ID (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_analytics_track_error(rac_stt_analytics_handle_t handle,
                                                   rac_result_t error_code,
                                                   const char* error_message, const char* operation,
                                                   const char* model_id,
                                                   const char* transcription_id);

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
RAC_API rac_result_t rac_stt_analytics_get_metrics(rac_stt_analytics_handle_t handle,
                                                   rac_stt_metrics_t* out_metrics);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_ANALYTICS_H */
