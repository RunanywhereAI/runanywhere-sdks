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
 * @param model_path File path to the model (used for loading) - REQUIRED
 * @param model_id Model identifier for telemetry (e.g., "smollm2-360m-q8_0")
 *                 Optional: if NULL, defaults to model_path
 * @param model_name Human-readable model name (e.g., "SmolLM2 360M Q8_0")
 *                   Optional: if NULL, defaults to model_id
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_load_model(rac_handle_t handle, const char* model_path,
                                                  const char* model_id, const char* model_name);

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

// =============================================================================
// LORA ADAPTER API
// =============================================================================

/**
 * @brief Load and apply a LoRA adapter
 *
 * Only supported when using the LlamaCPP backend.
 * Context is recreated internally and KV cache is cleared.
 *
 * @param handle Component handle
 * @param adapter_path Path to the LoRA adapter GGUF file
 * @param scale Adapter scale factor (0.0-1.0, default 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_load_lora(rac_handle_t handle,
                                                  const char* adapter_path,
                                                  float scale);

/**
 * @brief Remove a specific LoRA adapter by path
 *
 * @param handle Component handle
 * @param adapter_path Path used when loading the adapter
 * @return RAC_SUCCESS or RAC_ERROR_NOT_FOUND
 */
RAC_API rac_result_t rac_llm_component_remove_lora(rac_handle_t handle,
                                                    const char* adapter_path);

/**
 * @brief Remove all LoRA adapters
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_clear_lora(rac_handle_t handle);

/**
 * @brief Get loaded LoRA adapters info as JSON
 *
 * Returns JSON array: [{"path":"...", "scale":1.0, "applied":true}, ...]
 *
 * @param handle Component handle
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_get_lora_info(rac_handle_t handle,
                                                      char** out_json);

// =============================================================================
// DESTRUCTION
// =============================================================================

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
