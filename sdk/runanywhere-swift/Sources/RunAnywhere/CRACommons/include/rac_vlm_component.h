/**
 * @file rac_vlm_component.h
 * @brief RunAnywhere Commons - VLM Capability Component
 *
 * Actor-based VLM capability that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#ifndef RAC_VLM_COMPONENT_H
#define RAC_VLM_COMPONENT_H

#include "rac_lifecycle.h"
#include "rac_error.h"
#include "rac_vlm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// VLM COMPONENT API
// =============================================================================

/**
 * @brief Create a VLM capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the VLM component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_configure(rac_handle_t handle,
                                                 const rac_vlm_config_t* config);

/**
 * @brief Check if model is loaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_vlm_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * @param handle Component handle
 * @return Current model ID (NULL if not loaded)
 */
RAC_API const char* rac_vlm_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load a VLM model
 *
 * @param handle Component handle
 * @param model_path File path to the main model (LLM weights) - REQUIRED
 * @param mmproj_path File path to the vision projector (required for llama.cpp, NULL for MLX)
 * @param model_id Model identifier for telemetry (optional: if NULL, defaults to model_path)
 * @param model_name Human-readable model name (optional: if NULL, defaults to model_id)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_load_model(rac_handle_t handle, const char* model_path,
                                                  const char* mmproj_path, const char* model_id,
                                                  const char* model_name);

/**
 * @brief Load a VLM model by model ID using the global model registry
 *
 * Looks up the model in the global registry, resolves the model folder,
 * scans for the main .gguf and mmproj .gguf files, and loads them.
 * This is the preferred API — callers only need to provide the model ID.
 *
 * @param handle Component handle
 * @param model_id Model identifier (must be registered in the global registry)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_load_model_by_id(rac_handle_t handle, const char* model_id);

/**
 * @brief Resolve VLM model files within a directory
 *
 * Scans the given directory for .gguf files and identifies:
 * - Main model file: first .gguf NOT containing "mmproj" in its name
 * - Vision projector file: first .gguf containing "mmproj" in its name
 *
 * @param model_dir Path to the directory containing model files
 * @param out_model_path Output buffer for the main model file path
 * @param model_path_size Size of the model path output buffer
 * @param out_mmproj_path Output buffer for the mmproj file path (empty if not found)
 * @param mmproj_path_size Size of the mmproj path output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_resolve_model_files(const char* model_dir, char* out_model_path,
                                                 size_t model_path_size, char* out_mmproj_path,
                                                 size_t mmproj_path_size);

/**
 * @brief Unload the current model
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_cleanup(rac_handle_t handle);

/**
 * @brief Cancel ongoing generation
 *
 * Best-effort cancellation.
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_cancel(rac_handle_t handle);

/**
 * @brief Process an image with text prompt (non-streaming)
 *
 * @param handle Component handle
 * @param image Image input
 * @param prompt Text prompt
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                               const char* prompt, const rac_vlm_options_t* options,
                                               rac_vlm_result_t* out_result);

/**
 * @brief Check if streaming is supported
 *
 * @param handle Component handle
 * @return RAC_TRUE if streaming supported, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_vlm_component_supports_streaming(rac_handle_t handle);

/**
 * @brief Process an image with streaming
 *
 * @param handle Component handle
 * @param image Image input
 * @param prompt Text prompt
 * @param options Generation options (can be NULL for defaults)
 * @param token_callback Called for each generated token
 * @param complete_callback Called when generation completes
 * @param error_callback Called on error
 * @param user_data User context passed to callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_process_stream(
    rac_handle_t handle, const rac_vlm_image_t* image, const char* prompt,
    const rac_vlm_options_t* options, rac_vlm_component_token_callback_fn token_callback,
    rac_vlm_component_complete_callback_fn complete_callback,
    rac_vlm_component_error_callback_fn error_callback, void* user_data);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_vlm_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the VLM component
 *
 * @param handle Component handle
 */
RAC_API void rac_vlm_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_COMPONENT_H */
