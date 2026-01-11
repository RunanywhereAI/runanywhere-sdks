/**
 * @file rac_llm_events.h
 * @brief LLM-specific event types - 1:1 port of LLMEvent.swift
 *
 * All LLM-related events in one place.
 * Each event declares its destination (public, analytics, or both).
 *
 * Swift Source: Sources/RunAnywhere/Features/LLM/Analytics/LLMEvent.swift
 */

#ifndef RAC_LLM_EVENTS_H
#define RAC_LLM_EVENTS_H

#include "rac_types.h"
#include "rac_events.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// LLM EVENT TYPES
// =============================================================================

/**
 * @brief LLM event types enumeration
 * Mirrors Swift's LLMEvent cases
 */
typedef enum rac_llm_event_type {
    RAC_LLM_EVENT_MODEL_LOAD_STARTED = 0,
    RAC_LLM_EVENT_MODEL_LOAD_COMPLETED,
    RAC_LLM_EVENT_MODEL_LOAD_FAILED,
    RAC_LLM_EVENT_MODEL_UNLOADED,
    RAC_LLM_EVENT_MODEL_UNLOAD_STARTED,
    RAC_LLM_EVENT_GENERATION_STARTED,
    RAC_LLM_EVENT_FIRST_TOKEN,
    RAC_LLM_EVENT_STREAMING_UPDATE,
    RAC_LLM_EVENT_GENERATION_COMPLETED,
    RAC_LLM_EVENT_GENERATION_FAILED,
} rac_llm_event_type_t;

// =============================================================================
// LLM EVENT DATA STRUCTURES
// =============================================================================

/**
 * @brief Model load event data
 */
typedef struct rac_llm_model_load_event {
    const char* model_id;
    int64_t model_size_bytes;
    rac_inference_framework_t framework;
    double duration_ms;        /**< Only for completed events */
    rac_result_t error_code;   /**< Only for failed events */
    const char* error_message; /**< Only for failed events */
} rac_llm_model_load_event_t;

/**
 * @brief Generation event data
 */
typedef struct rac_llm_generation_event {
    const char* generation_id;
    const char* model_id;
    rac_bool_t is_streaming;
    rac_inference_framework_t framework;

    /** For completed events */
    int32_t input_tokens;
    int32_t output_tokens;
    double duration_ms;
    double tokens_per_second;
    double time_to_first_token_ms; /**< -1 if not applicable */
    float temperature;
    int32_t max_tokens;
    int32_t context_length;

    /** For streaming updates */
    int32_t tokens_generated;

    /** For failed events */
    rac_result_t error_code;
    const char* error_message;
} rac_llm_generation_event_t;

// =============================================================================
// EVENT PUBLISHING FUNCTIONS
// =============================================================================

/**
 * @brief Publish a model load started event
 *
 * @param model_id Model identifier
 * @param model_size_bytes Size of model in bytes (0 if unknown)
 * @param framework Inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_model_load_started(const char* model_id,
                                                      int64_t model_size_bytes,
                                                      rac_inference_framework_t framework);

/**
 * @brief Publish a model load completed event
 *
 * @param model_id Model identifier
 * @param duration_ms Load duration in milliseconds
 * @param model_size_bytes Size of model in bytes
 * @param framework Inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_model_load_completed(const char* model_id, double duration_ms,
                                                        int64_t model_size_bytes,
                                                        rac_inference_framework_t framework);

/**
 * @brief Publish a model load failed event
 *
 * @param model_id Model identifier
 * @param error_code Error code
 * @param error_message Error message
 * @param framework Inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_model_load_failed(const char* model_id, rac_result_t error_code,
                                                     const char* error_message,
                                                     rac_inference_framework_t framework);

/**
 * @brief Publish a model unloaded event
 *
 * @param model_id Model identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_model_unloaded(const char* model_id);

/**
 * @brief Publish a generation started event
 *
 * @param generation_id Generation identifier
 * @param model_id Model identifier
 * @param is_streaming Whether this is streaming generation
 * @param framework Inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_generation_started(const char* generation_id,
                                                      const char* model_id, rac_bool_t is_streaming,
                                                      rac_inference_framework_t framework);

/**
 * @brief Publish a first token event (streaming only)
 *
 * @param generation_id Generation identifier
 * @param model_id Model identifier
 * @param time_to_first_token_ms Time to first token in milliseconds
 * @param framework Inference framework
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_first_token(const char* generation_id, const char* model_id,
                                               double time_to_first_token_ms,
                                               rac_inference_framework_t framework);

/**
 * @brief Publish a streaming update event
 *
 * @param generation_id Generation identifier
 * @param tokens_generated Number of tokens generated so far
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_streaming_update(const char* generation_id,
                                                    int32_t tokens_generated);

/**
 * @brief Publish a generation completed event
 *
 * @param event Generation event data
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_generation_completed(const rac_llm_generation_event_t* event);

/**
 * @brief Publish a generation failed event
 *
 * @param generation_id Generation identifier
 * @param error_code Error code
 * @param error_message Error message
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_event_generation_failed(const char* generation_id,
                                                     rac_result_t error_code,
                                                     const char* error_message);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * @brief Get the event type string for an LLM event type
 *
 * @param event_type The LLM event type
 * @return Event type string (never NULL)
 */
RAC_API const char* rac_llm_event_type_string(rac_llm_event_type_t event_type);

/**
 * @brief Get the event destination for an LLM event type
 *
 * @param event_type The LLM event type
 * @return Event destination
 */
RAC_API rac_event_destination_t rac_llm_event_destination(rac_llm_event_type_t event_type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_EVENTS_H */
