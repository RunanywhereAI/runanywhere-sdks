/**
 * @file rac_llm_component.h
 * @brief RunAnywhere Commons - LLM Capability Component
 *
 * C port of Swift's LLMCapability.swift from:
 * Sources/RunAnywhere/Features/LLM/LLMCapability.swift
 *
 * Actor-based LLM capability that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - Component lifecycle/generation entry points
 *     (rac_llm_component_create, configure, load_model, unload,
 *     cleanup, cancel, generate, generate_stream,
 *     get_state, get_metrics, destroy):
 *     `delete after SDK migration` for SDK callers — replaced by
 *     rac_model_lifecycle_load_proto + rac_llm_*_proto.
 *   - LoRA helpers (rac_llm_component_load_lora, remove_lora,
 *     clear_lora, get_lora_info, check_lora_compat): `delete after
 *     SDK migration`. Use rac_lora_*_proto.
 */

#ifndef RAC_LLM_COMPONENT_H
#define RAC_LLM_COMPONENT_H

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_types.h"

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
RAC_API rac_result_t rac_llm_component_load_lora(rac_handle_t handle, const char* adapter_path,
                                                 float scale);

/**
 * @brief Remove a specific LoRA adapter by path
 *
 * @param handle Component handle
 * @param adapter_path Path used when loading the adapter
 * @return RAC_SUCCESS or RAC_ERROR_NOT_FOUND
 */
RAC_API rac_result_t rac_llm_component_remove_lora(rac_handle_t handle, const char* adapter_path);

/**
 * @brief Remove all LoRA adapters
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_clear_lora(rac_handle_t handle);

/**
 * @brief Check if the current backend supports LoRA adapters
 *
 * Verifies that a model is loaded and the active backend exposes LoRA operations.
 * This is a lightweight pre-check; actual file validation occurs during load.
 *
 * @param handle Component handle
 * @param adapter_path Path to the LoRA adapter GGUF file (must be non-empty)
 * @param out_error Output: error message if incompatible (caller must free with rac_free), NULL if
 * compatible
 * @return RAC_SUCCESS if the backend supports LoRA, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           safety net used by `rac_lora_apply_proto` at load time. SDKs
 *           consume LoRA compatibility through the `rac_lora_*_proto` API.
 */
rac_result_t rac_llm_component_check_lora_compat(rac_handle_t handle, const char* adapter_path,
                                                 char** out_error);

// =============================================================================
// ADAPTIVE CONTEXT API - KV Cache Prefix-Caching for Multi-Turn Sessions
// =============================================================================

/**
 * @brief Inject a system prompt into the KV cache at position 0
 *
 * Clears existing KV cache, then seeds it with the given system prompt.
 * Call once at session start to avoid re-tokenizing the prompt every turn.
 *
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if the active backend does not
 * implement adaptive context (e.g., only LlamaCPP supports it today).
 *
 * @param handle Component handle
 * @param prompt System prompt text (must be non-NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_inject_system_prompt(rac_handle_t handle, const char* prompt);

/**
 * @brief Append text to the KV cache after current content
 *
 * Does not clear existing KV state — accumulates context incrementally.
 * Use after inject_system_prompt to append user turns, assistant responses,
 * or RAG chunks without re-processing the entire conversation.
 *
 * @warning Callers MUST call rac_llm_component_clear_context() at session
 *          boundaries (user switch, session end, memory pressure) to prevent
 *          unbounded KV cache growth that will lead to OS-level OOM termination.
 *
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if the active backend does not
 * implement adaptive context.
 *
 * @param handle Component handle
 * @param text Text to append (must be non-NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_append_context(rac_handle_t handle, const char* text);

/**
 * @brief Generate a response from accumulated KV cache state
 *
 * Unlike rac_llm_component_generate(), this does NOT clear the KV cache first.
 * Use after inject_system_prompt + append_context to generate from accumulated
 * state, preserving the KV cache for subsequent turns.
 *
 * @warning This call is BLOCKING (non-streaming). It will monopolize the calling
 *          thread for the entire decode duration (potentially several seconds on
 *          mobile hardware). On platforms with cooperative thread pools (e.g.,
 *          Swift async/await), callers MUST offload this to a non-cooperative
 *          thread or accept that overlapping generation requests may deadlock.
 *          A streaming variant (generate_stream_from_context) is planned as a
 *          follow-up.
 *
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if the active backend does not
 * implement adaptive context.
 *
 * @param handle Component handle
 * @param query Query/suffix text to append before generation (must be non-NULL)
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free with rac_llm_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_generate_from_context(rac_handle_t handle, const char* query,
                                                              const rac_llm_options_t* options,
                                                              rac_llm_result_t* out_result);

/**
 * @brief Clear all KV cache state
 *
 * Resets the LLM's context for a fresh adaptive query cycle. Call at session
 * boundaries, on user switch, or when memory pressure is detected to prevent
 * unbounded KV cache growth.
 *
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if the active backend does not
 * implement adaptive context. Returns RAC_SUCCESS if no model is loaded
 * (no context to clear).
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_component_clear_context(rac_handle_t handle);

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
