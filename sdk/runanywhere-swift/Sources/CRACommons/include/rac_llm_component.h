/**
 * @file rac_llm_component.h
 * @brief RunAnywhere Commons - LLM Capability Component
 *
 * C port of Swift's LLMCapability.swift from:
 * Sources/RunAnywhere/Features/LLM/LLMCapability.swift
 *
 * Actor-based LLM capability that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#ifndef RAC_LLM_COMPONENT_H
#define RAC_LLM_COMPONENT_H

#include "rac_lifecycle.h"
#include "rac_error.h"
#include "rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// NOTE: rac_llm_config_t is defined in rac_llm_types.h (included above)

// =============================================================================
// STREAMING CALLBACKS - For component-level streaming
// =============================================================================

/**
 * @brief Streaming callback for token-by-token generation
 *
 * @param token The generated token
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop
 */
typedef rac_bool_t (*rac_llm_component_token_callback_fn)(const char* token, void* user_data);

/**
 * @brief Streaming completion callback
 *
 * Called when streaming is complete with final metrics.
 *
 * @param result Final generation result with metrics
 * @param user_data User-provided context
 */
typedef void (*rac_llm_component_complete_callback_fn)(const rac_llm_result_t* result,
                                                       void* user_data);

/**
 * @brief Streaming error callback
 *
 * Called if streaming fails.
 *
 * @param error_code Error code
 * @param error_message Error message
 * @param user_data User-provided context
 */
typedef void (*rac_llm_component_error_callback_fn)(rac_result_t error_code,
                                                    const char* error_message, void* user_data);

// =============================================================================
// LLM COMPONENT API - Mirrors Swift's LLMCapability
// =============================================================================

/**
 * @brief Create an LLM capability component
 *
 * Mirrors Swift's LLMCapability.init()
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the LLM component
 *
 * Mirrors Swift's LLMCapability.configure(_:)
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_configure(rac_handle_t handle,
                                                 const rac_llm_config_t* config);

/**
 * @brief Check if model is loaded
 *
 * Mirrors Swift's LLMCapability.isModelLoaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_llm_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * Mirrors Swift's LLMCapability.currentModelId
 *
 * @param handle Component handle
 * @return Current model ID (NULL if not loaded)
 */
RAC_API const char* rac_llm_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load a model
 *
 * Mirrors Swift's LLMCapability.loadModel(_:)
 *
 * @param handle Component handle
 * @param model_id Model ID to load
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_load_model(rac_handle_t handle, const char* model_id);

/**
 * @brief Unload the current model
 *
 * Mirrors Swift's LLMCapability.unload()
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * Mirrors Swift's LLMCapability.cleanup()
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_cleanup(rac_handle_t handle);

/**
 * @brief Cancel ongoing generation
 *
 * Mirrors Swift's LLMCapability.cancel()
 * Best-effort cancellation.
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_cancel(rac_handle_t handle);

/**
 * @brief Generate text (non-streaming)
 *
 * Mirrors Swift's LLMCapability.generate(_:options:)
 *
 * @param handle Component handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_generate(rac_handle_t handle, const char* prompt,
                                                const rac_llm_options_t* options,
                                                rac_llm_result_t* out_result);

/**
 * @brief Check if streaming is supported
 *
 * Mirrors Swift's LLMCapability.supportsStreaming
 *
 * @param handle Component handle
 * @return RAC_TRUE if streaming supported, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_llm_component_supports_streaming(rac_handle_t handle);

/**
 * @brief Generate text with streaming
 *
 * Mirrors Swift's LLMCapability.generateStream(_:options:)
 *
 * @param handle Component handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param token_callback Called for each generated token
 * @param complete_callback Called when generation completes
 * @param error_callback Called on error
 * @param user_data User context passed to callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_generate_stream(
    rac_handle_t handle, const char* prompt, const rac_llm_options_t* options,
    rac_llm_component_token_callback_fn token_callback,
    rac_llm_component_complete_callback_fn complete_callback,
    rac_llm_component_error_callback_fn error_callback, void* user_data);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_llm_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the LLM component
 *
 * @param handle Component handle
 */
RAC_API void rac_llm_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_COMPONENT_H */
