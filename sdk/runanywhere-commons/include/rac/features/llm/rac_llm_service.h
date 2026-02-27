/**
 * @file rac_llm_service.h
 * @brief RunAnywhere Commons - LLM Service Interface
 *
 * Defines the generic LLM service API and vtable for multi-backend dispatch.
 * Backends (LlamaCpp, Platform, ONNX) implement the vtable and register
 * with the service registry.
 */

#ifndef RAC_LLM_SERVICE_H
#define RAC_LLM_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * LLM Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_llm_service_ops {
    /** Initialize the service with a model path */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /** Generate text (blocking) */
    rac_result_t (*generate)(void* impl, const char* prompt, const rac_llm_options_t* options,
                             rac_llm_result_t* out_result);

    /** Generate text with streaming callback */
    rac_result_t (*generate_stream)(void* impl, const char* prompt,
                                    const rac_llm_options_t* options,
                                    rac_llm_stream_callback_fn callback, void* user_data);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_llm_info_t* out_info);

    /** Cancel ongoing generation */
    rac_result_t (*cancel)(void* impl);

    /** Cleanup/unload model (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);

    /** Load a LoRA adapter (optional, NULL if not supported) */
    rac_result_t (*load_lora)(void* impl, const char* adapter_path, float scale);

    /** Remove a LoRA adapter by path (optional, NULL if not supported) */
    rac_result_t (*remove_lora)(void* impl, const char* adapter_path);

    /** Clear all LoRA adapters (optional, NULL if not supported) */
    rac_result_t (*clear_lora)(void* impl);

    /** Get loaded LoRA adapters info as JSON (optional, NULL if not supported) */
    rac_result_t (*get_lora_info)(void* impl, char** out_json);

    /** Inject system prompt into KV cache at position 0 (optional, NULL if not supported) */
    rac_result_t (*inject_system_prompt)(void* impl, const char* prompt);

    /** Append text to KV cache after current content (optional, NULL if not supported) */
    rac_result_t (*append_context)(void* impl, const char* text);

    /**
     * Generate response from accumulated KV cache state (optional, NULL if not supported).
     * Unlike generate(), does NOT clear KV cache first.
     */
    rac_result_t (*generate_from_context)(void* impl, const char* query,
                                          const rac_llm_options_t* options,
                                          rac_llm_result_t* out_result);

    /** Clear all KV cache state (optional, NULL if not supported) */
    rac_result_t (*clear_context)(void* impl);
} rac_llm_service_ops_t;

/**
 * LLM Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_llm_service {
    /** Vtable with backend operations */
    const rac_llm_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_llm_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create an LLM service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_id Model identifier (registry ID or path to model file)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle);

/**
 * @brief Initialize an LLM service
 *
 * @param handle Service handle
 * @param model_path Path to the model file (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path);

/**
 * @brief Generate text from prompt
 *
 * @param handle Service handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free with rac_llm_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                                      const rac_llm_options_t* options,
                                      rac_llm_result_t* out_result);

/**
 * @brief Stream generate text token by token
 *
 * @param handle Service handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param callback Callback for each token
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_stream_callback_fn callback, void* user_data);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_get_info(rac_handle_t handle, rac_llm_info_t* out_info);

/**
 * @brief Cancel ongoing generation
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_cancel(rac_handle_t handle);

/**
 * @brief Cleanup and release model resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_cleanup(rac_handle_t handle);

/**
 * @brief Destroy an LLM service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_llm_destroy(rac_handle_t handle);

/**
 * @brief Free an LLM result
 *
 * @param result Result to free
 */
RAC_API void rac_llm_result_free(rac_llm_result_t* result);

// =============================================================================
// ADAPTIVE CONTEXT API - For RAG and similar pipelines
// =============================================================================

/**
 * @brief Inject a system prompt into the LLM's KV cache at position 0
 *
 * Clears existing KV cache, then seeds with the given prompt.
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if backend doesn't support it.
 *
 * @param handle Service handle
 * @param prompt System prompt text
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_inject_system_prompt(rac_handle_t handle, const char* prompt);

/**
 * @brief Append text to the LLM's KV cache after current content
 *
 * Does not clear existing KV state — accumulates context incrementally.
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if backend doesn't support it.
 *
 * @param handle Service handle
 * @param text Text to append
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_append_context(rac_handle_t handle, const char* text);

/**
 * @brief Generate a response from accumulated KV cache state
 *
 * Unlike rac_llm_generate(), this does NOT clear the KV cache first.
 * Use after inject_system_prompt + append_context to generate from accumulated state.
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if backend doesn't support it.
 *
 * @param handle Service handle
 * @param query Query/suffix text to append before generation
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_generate_from_context(rac_handle_t handle, const char* query,
                                                    const rac_llm_options_t* options,
                                                    rac_llm_result_t* out_result);

/**
 * @brief Clear all KV cache state
 *
 * Resets the LLM's context for a fresh adaptive query cycle.
 * Optional — returns RAC_ERROR_NOT_SUPPORTED if backend doesn't support it.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_clear_context(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_SERVICE_H */
