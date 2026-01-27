/**
 * @file rac_diffusion_component.h
 * @brief RunAnywhere Commons - Diffusion Capability Component
 *
 * Actor-based diffusion capability that owns model lifecycle and generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 *
 * Supports:
 * - Text-to-image generation
 * - Image-to-image transformation
 * - Inpainting with mask
 * - Progress reporting with optional intermediate images
 */

#ifndef RAC_DIFFUSION_COMPONENT_H
#define RAC_DIFFUSION_COMPONENT_H

#include "rac_lifecycle.h"
#include "rac_error.h"
#include "rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// DIFFUSION COMPONENT API - Component lifecycle and generation
// =============================================================================

/**
 * @brief Create a diffusion capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the diffusion component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_configure(rac_handle_t handle,
                                                       const rac_diffusion_config_t* config);

/**
 * @brief Check if model is loaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_diffusion_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * @param handle Component handle
 * @return Current model ID (NULL if not loaded)
 */
RAC_API const char* rac_diffusion_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load a diffusion model
 *
 * @param handle Component handle
 * @param model_path Path to the model directory
 * @param model_id Model identifier for telemetry
 * @param model_name Human-readable model name
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_load_model(rac_handle_t handle, const char* model_path,
                                                        const char* model_id,
                                                        const char* model_name);

/**
 * @brief Unload the current model
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_cleanup(rac_handle_t handle);

/**
 * @brief Cancel ongoing generation
 *
 * Best-effort cancellation.
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_cancel(rac_handle_t handle);

/**
 * @brief Generate an image (non-streaming)
 *
 * Blocking call that generates an image from the prompt.
 *
 * @param handle Component handle
 * @param options Generation options
 * @param out_result Output: Generation result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_generate(rac_handle_t handle,
                                                      const rac_diffusion_options_t* options,
                                                      rac_diffusion_result_t* out_result);

/**
 * @brief Generate an image with progress callbacks
 *
 * Non-blocking call with progress reporting via callbacks.
 *
 * @param handle Component handle
 * @param options Generation options
 * @param progress_callback Called for each progress update
 * @param complete_callback Called when generation completes
 * @param error_callback Called on error
 * @param user_data User context passed to callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_generate_with_callbacks(
    rac_handle_t handle, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback,
    rac_diffusion_complete_callback_fn complete_callback,
    rac_diffusion_error_callback_fn error_callback, void* user_data);

/**
 * @brief Get supported capabilities
 *
 * Returns a bitmask of supported capabilities.
 *
 * @param handle Component handle
 * @return Capability bitmask (RAC_DIFFUSION_CAP_* flags)
 */
RAC_API uint32_t rac_diffusion_component_get_capabilities(rac_handle_t handle);

/**
 * @brief Get service information
 *
 * @param handle Component handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_get_info(rac_handle_t handle,
                                                      rac_diffusion_info_t* out_info);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_diffusion_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_component_get_metrics(rac_handle_t handle,
                                                         rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the diffusion component
 *
 * @param handle Component handle
 */
RAC_API void rac_diffusion_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_COMPONENT_H */
