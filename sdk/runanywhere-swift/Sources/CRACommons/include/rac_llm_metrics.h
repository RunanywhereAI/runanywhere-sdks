/**
 * @file rac_llm_metrics.h
 * @brief LLM Streaming Metrics - TTFT and Token Rate Tracking
 *
 * C port of Swift's StreamingMetricsCollector and GenerationAnalyticsService.
 * Swift Source: Sources/RunAnywhere/Features/LLM/LLMCapability.swift (StreamingMetricsCollector)
 * Swift Source: Sources/RunAnywhere/Features/LLM/Analytics/GenerationAnalyticsService.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_LLM_METRICS_H
#define RAC_LLM_METRICS_H

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES - Mirrors Swift's GenerationMetrics and StreamingMetricsCollector
// =============================================================================

/**
 * @brief Generation metrics snapshot.
 * Mirrors Swift's GenerationMetrics struct.
 */
typedef struct rac_generation_metrics {
    /** Total generation count */
    int32_t total_generations;

    /** Streaming generation count */
    int32_t streaming_generations;

    /** Non-streaming generation count */
    int32_t non_streaming_generations;

    /** Average time-to-first-token in ms (streaming only) */
    double average_ttft_ms;

    /** Average tokens per second */
    double average_tokens_per_second;

    /** Total input tokens processed */
    int64_t total_input_tokens;

    /** Total output tokens generated */
    int64_t total_output_tokens;

    /** Service start time (Unix timestamp ms) */
    int64_t start_time_ms;

    /** Last event time (Unix timestamp ms) */
    int64_t last_event_time_ms;
} rac_generation_metrics_t;

/**
 * @brief Default generation metrics.
 */
static const rac_generation_metrics_t RAC_GENERATION_METRICS_DEFAULT = {
    .total_generations = 0,
    .streaming_generations = 0,
    .non_streaming_generations = 0,
    .average_ttft_ms = 0.0,
    .average_tokens_per_second = 0.0,
    .total_input_tokens = 0,
    .total_output_tokens = 0,
    .start_time_ms = 0,
    .last_event_time_ms = 0};

/**
 * @brief Streaming generation result.
 * Mirrors Swift's LLMGenerationResult for streaming.
 */
typedef struct rac_streaming_result {
    /** Generated text (owned, must be freed) */
    char* text;

    /** Thinking/reasoning content if any (owned, must be freed, can be NULL) */
    char* thinking_content;

    /** Input tokens processed */
    int32_t input_tokens;

    /** Output tokens generated */
    int32_t output_tokens;

    /** Model ID used (owned, must be freed) */
    char* model_id;

    /** Total latency in milliseconds */
    double latency_ms;

    /** Tokens generated per second */
    double tokens_per_second;

    /** Time-to-first-token in milliseconds (0 if not streaming) */
    double ttft_ms;

    /** Thinking tokens (for reasoning models) */
    int32_t thinking_tokens;

    /** Response tokens (excluding thinking) */
    int32_t response_tokens;
} rac_streaming_result_t;

/**
 * @brief Default streaming result.
 */
static const rac_streaming_result_t RAC_STREAMING_RESULT_DEFAULT = {.text = RAC_NULL,
                                                                    .thinking_content = RAC_NULL,
                                                                    .input_tokens = 0,
                                                                    .output_tokens = 0,
                                                                    .model_id = RAC_NULL,
                                                                    .latency_ms = 0.0,
                                                                    .tokens_per_second = 0.0,
                                                                    .ttft_ms = 0.0,
                                                                    .thinking_tokens = 0,
                                                                    .response_tokens = 0};

// =============================================================================
// OPAQUE HANDLES
// =============================================================================

/**
 * @brief Opaque handle for streaming metrics collector.
 */
typedef struct rac_streaming_metrics_collector* rac_streaming_metrics_handle_t;

/**
 * @brief Opaque handle for generation analytics service.
 */
typedef struct rac_generation_analytics* rac_generation_analytics_handle_t;

// =============================================================================
// STREAMING METRICS COLLECTOR API - Mirrors Swift's StreamingMetricsCollector
// =============================================================================

/**
 * @brief Create a streaming metrics collector.
 *
 * @param model_id Model ID being used
 * @param generation_id Unique generation identifier
 * @param prompt_length Length of input prompt (for token estimation)
 * @param out_handle Output: Handle to the created collector
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_create(const char* model_id, const char* generation_id,
                                                  int32_t prompt_length,
                                                  rac_streaming_metrics_handle_t* out_handle);

/**
 * @brief Destroy a streaming metrics collector.
 *
 * @param handle Collector handle
 */
RAC_API void rac_streaming_metrics_destroy(rac_streaming_metrics_handle_t handle);

/**
 * @brief Mark the start of generation.
 *
 * Mirrors Swift's StreamingMetricsCollector.markStart().
 *
 * @param handle Collector handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_mark_start(rac_streaming_metrics_handle_t handle);

/**
 * @brief Record a token received during streaming.
 *
 * Mirrors Swift's StreamingMetricsCollector.recordToken(_:).
 * First call records TTFT.
 *
 * @param handle Collector handle
 * @param token Token string received
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_record_token(rac_streaming_metrics_handle_t handle,
                                                        const char* token);

/**
 * @brief Mark generation as complete.
 *
 * Mirrors Swift's StreamingMetricsCollector.markComplete().
 *
 * @param handle Collector handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_mark_complete(rac_streaming_metrics_handle_t handle);

/**
 * @brief Mark generation as failed.
 *
 * Mirrors Swift's StreamingMetricsCollector.recordError(_:).
 *
 * @param handle Collector handle
 * @param error_code Error code
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_mark_failed(rac_streaming_metrics_handle_t handle,
                                                       rac_result_t error_code);

/**
 * @brief Get the generation result.
 *
 * Mirrors Swift's StreamingMetricsCollector.buildResult().
 * Only valid after markComplete() is called.
 *
 * @param handle Collector handle
 * @param out_result Output: Streaming result (must be freed with rac_streaming_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_get_result(rac_streaming_metrics_handle_t handle,
                                                      rac_streaming_result_t* out_result);

/**
 * @brief Get current TTFT in milliseconds.
 *
 * @param handle Collector handle
 * @param out_ttft_ms Output: TTFT in ms (0 if first token not yet received)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_get_ttft(rac_streaming_metrics_handle_t handle,
                                                    double* out_ttft_ms);

/**
 * @brief Get current token count.
 *
 * @param handle Collector handle
 * @param out_token_count Output: Number of tokens recorded
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_get_token_count(rac_streaming_metrics_handle_t handle,
                                                           int32_t* out_token_count);

/**
 * @brief Get accumulated text.
 *
 * @param handle Collector handle
 * @param out_text Output: Accumulated text (owned, must be freed)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_streaming_metrics_get_text(rac_streaming_metrics_handle_t handle,
                                                    char** out_text);

// =============================================================================
// GENERATION ANALYTICS SERVICE API - Mirrors Swift's GenerationAnalyticsService
// =============================================================================

/**
 * @brief Create a generation analytics service.
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_create(rac_generation_analytics_handle_t* out_handle);

/**
 * @brief Destroy a generation analytics service.
 *
 * @param handle Service handle
 */
RAC_API void rac_generation_analytics_destroy(rac_generation_analytics_handle_t handle);

/**
 * @brief Start tracking a non-streaming generation.
 *
 * Mirrors Swift's GenerationAnalyticsService.startGeneration().
 *
 * @param handle Service handle
 * @param generation_id Unique generation identifier
 * @param model_id Model ID
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_start(rac_generation_analytics_handle_t handle,
                                                    const char* generation_id,
                                                    const char* model_id);

/**
 * @brief Start tracking a streaming generation.
 *
 * Mirrors Swift's GenerationAnalyticsService.startStreamingGeneration().
 *
 * @param handle Service handle
 * @param generation_id Unique generation identifier
 * @param model_id Model ID
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_start_streaming(
    rac_generation_analytics_handle_t handle, const char* generation_id, const char* model_id);

/**
 * @brief Track first token received (streaming only).
 *
 * Mirrors Swift's GenerationAnalyticsService.trackFirstToken().
 *
 * @param handle Service handle
 * @param generation_id Generation identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_track_first_token(
    rac_generation_analytics_handle_t handle, const char* generation_id);

/**
 * @brief Track streaming update.
 *
 * Mirrors Swift's GenerationAnalyticsService.trackStreamingUpdate().
 *
 * @param handle Service handle
 * @param generation_id Generation identifier
 * @param tokens_generated Number of tokens generated so far
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_track_streaming_update(
    rac_generation_analytics_handle_t handle, const char* generation_id, int32_t tokens_generated);

/**
 * @brief Complete a generation.
 *
 * Mirrors Swift's GenerationAnalyticsService.completeGeneration().
 *
 * @param handle Service handle
 * @param generation_id Generation identifier
 * @param input_tokens Number of input tokens
 * @param output_tokens Number of output tokens
 * @param model_id Model ID used
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_complete(rac_generation_analytics_handle_t handle,
                                                       const char* generation_id,
                                                       int32_t input_tokens, int32_t output_tokens,
                                                       const char* model_id);

/**
 * @brief Track generation failure.
 *
 * Mirrors Swift's GenerationAnalyticsService.trackGenerationFailed().
 *
 * @param handle Service handle
 * @param generation_id Generation identifier
 * @param error_code Error code
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_track_failed(rac_generation_analytics_handle_t handle,
                                                           const char* generation_id,
                                                           rac_result_t error_code);

/**
 * @brief Get aggregated metrics.
 *
 * Mirrors Swift's GenerationAnalyticsService.getMetrics().
 *
 * @param handle Service handle
 * @param out_metrics Output: Generation metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_get_metrics(rac_generation_analytics_handle_t handle,
                                                          rac_generation_metrics_t* out_metrics);

/**
 * @brief Reset metrics.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_generation_analytics_reset(rac_generation_analytics_handle_t handle);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free a streaming result.
 *
 * @param result Result to free
 */
RAC_API void rac_streaming_result_free(rac_streaming_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_METRICS_H */
