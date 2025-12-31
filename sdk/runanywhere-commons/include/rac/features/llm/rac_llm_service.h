/**
 * @file rac_llm_service.h
 * @brief RunAnywhere Commons - LLM Service Interface (Protocol)
 *
 * C port of Swift's LLMService protocol from:
 * Sources/RunAnywhere/Features/LLM/Protocol/LLMService.swift
 *
 * This header defines the service interface. For data types,
 * see rac_llm_types.h.
 */

#ifndef RAC_LLM_SERVICE_H
#define RAC_LLM_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE INTERFACE - Mirrors Swift's LLMService protocol
// =============================================================================

/**
 * @brief Create an LLM service
 *
 * @param model_path Path to the model file (can be NULL for some providers)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_create(const char* model_path, rac_handle_t* out_handle);

/**
 * @brief Initialize an LLM service
 *
 * Mirrors Swift's LLMService.initialize(modelPath:)
 *
 * @param handle Service handle
 * @param model_path Path to the model file (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path);

/**
 * @brief Generate text from prompt
 *
 * Mirrors Swift's LLMService.generate(prompt:options:)
 *
 * @param handle Service handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free text with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                                      const rac_llm_options_t* options,
                                      rac_llm_result_t* out_result);

/**
 * @brief Stream generate text token by token
 *
 * Mirrors Swift's LLMService.streamGenerate(prompt:options:onToken:)
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
 * Mirrors Swift's LLMService.cancel()
 * Best-effort operation; not all backends support mid-generation cancellation.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_llm_cancel(rac_handle_t handle);

/**
 * @brief Cleanup and release resources
 *
 * Mirrors Swift's LLMService.cleanup()
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

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_SERVICE_H */
