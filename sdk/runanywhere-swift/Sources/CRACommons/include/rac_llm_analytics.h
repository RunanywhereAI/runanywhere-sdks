/**
 * @file rac_llm_analytics.h
 * @brief LLM Generation analytics service - 1:1 port of GenerationAnalyticsService.swift
 *
 * Tracks generation operations and metrics.
 * Lifecycle events are handled by the lifecycle manager.
 *
 * NOTE: Token estimation uses ~4 chars/token (approximation, not exact tokenizer count).
 * Actual token counts may vary depending on the model's tokenizer and input content.
 *
 * Swift Source: Sources/RunAnywhere/Features/LLM/Analytics/GenerationAnalyticsService.swift
 */

#ifndef RAC_LLM_ANALYTICS_H
#define RAC_LLM_ANALYTICS_H

#include "rac_types.h"
#include "rac_llm_types.h"
#include "rac_llm_metrics.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle for LLM analytics service
 */
typedef struct rac_llm_analytics_s* rac_llm_analytics_handle_t;

// Note: rac_generation_metrics_t is defined in rac_llm_metrics.h

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create an LLM analytics service instance
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_create(rac_llm_analytics_handle_t* out_handle);

/**
 * @brief Destroy an LLM analytics service instance
 *
 * @param handle Handle to destroy
 */
RAC_API void rac_llm_analytics_destroy(rac_llm_analytics_handle_t handle);

// =============================================================================
// GENERATION TRACKING
// =============================================================================

/**
 * @brief Start tracking a non-streaming generation
 *
 * Mirrors Swift's startGeneration()
 *
 * @param handle Analytics service handle
 * @param model_id The model ID being used
 * @param framework The inference framework type (can be RAC_INFERENCE_FRAMEWORK_UNKNOWN)
 * @param temperature Generation temperature (NULL for default)
 * @param max_tokens Maximum tokens to generate (NULL for default)
 * @param context_length Context window size (NULL for default)
 * @param out_generation_id Output: Generated unique ID (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_start_generation(
    rac_llm_analytics_handle_t handle,
    const char* model_id,
    rac_inference_framework_t framework,
    const float* temperature,
    const int32_t* max_tokens,
    const int32_t* context_length,
    char** out_generation_id
);

/**
 * @brief Start tracking a streaming generation
 *
 * Mirrors Swift's startStreamingGeneration()
 *
 * @param handle Analytics service handle
 * @param model_id The model ID being used
 * @param framework The inference framework type
 * @param temperature Generation temperature (NULL for default)
 * @param max_tokens Maximum tokens to generate (NULL for default)
 * @param context_length Context window size (NULL for default)
 * @param out_generation_id Output: Generated unique ID (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_start_streaming_generation(
    rac_llm_analytics_handle_t handle,
    const char* model_id,
    rac_inference_framework_t framework,
    const float* temperature,
    const int32_t* max_tokens,
    const int32_t* context_length,
    char** out_generation_id
);

/**
 * @brief Track first token for streaming generation (TTFT metric)
 *
 * Only applicable for streaming generations. Call is ignored for non-streaming.
 *
 * @param handle Analytics service handle
 * @param generation_id The generation ID from start_streaming_generation
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_track_first_token(
    rac_llm_analytics_handle_t handle,
    const char* generation_id
);

/**
 * @brief Track streaming update (analytics only)
 *
 * Only applicable for streaming generations.
 *
 * @param handle Analytics service handle
 * @param generation_id The generation ID
 * @param tokens_generated Number of tokens generated so far
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_track_streaming_update(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    int32_t tokens_generated
);

/**
 * @brief Complete a generation (works for both streaming and non-streaming)
 *
 * @param handle Analytics service handle
 * @param generation_id The generation ID
 * @param input_tokens Number of input tokens processed
 * @param output_tokens Number of output tokens generated
 * @param model_id The model ID used
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_complete_generation(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    int32_t input_tokens,
    int32_t output_tokens,
    const char* model_id
);

/**
 * @brief Track generation failure
 *
 * @param handle Analytics service handle
 * @param generation_id The generation ID
 * @param error_code Error code
 * @param error_message Error message
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_track_generation_failed(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    rac_result_t error_code,
    const char* error_message
);

/**
 * @brief Track an error during LLM operations
 *
 * @param handle Analytics service handle
 * @param error_code Error code
 * @param error_message Error message
 * @param operation Operation that failed
 * @param model_id Model ID (can be NULL)
 * @param generation_id Generation ID (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_analytics_track_error(
    rac_llm_analytics_handle_t handle,
    rac_result_t error_code,
    const char* error_message,
    const char* operation,
    const char* model_id,
    const char* generation_id
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
RAC_API rac_result_t rac_llm_analytics_get_metrics(
    rac_llm_analytics_handle_t handle,
    rac_generation_metrics_t* out_metrics
);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_ANALYTICS_H */
