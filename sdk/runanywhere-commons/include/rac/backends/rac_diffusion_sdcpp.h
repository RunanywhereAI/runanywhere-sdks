/**
 * @file rac_diffusion_sdcpp.h
 * @brief RunAnywhere Commons - stable-diffusion.cpp Backend API
 *
 * Cross-platform diffusion inference backend using stable-diffusion.cpp (ggml).
 * Supports SD 1.5, SD 2.1, SDXL, SD3, FLUX models on CPU, Metal, Vulkan, OpenCL.
 * Model formats: .safetensors, .gguf, .ckpt
 *
 * This backend provides the same diffusion service vtable as CoreML,
 * allowing both to coexist and be selected via the service registry.
 */

#ifndef RAC_DIFFUSION_SDCPP_H
#define RAC_DIFFUSION_SDCPP_H

#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// BACKEND LIFECYCLE
// =============================================================================

/**
 * @brief Create a new sd.cpp diffusion backend instance.
 * @return Opaque handle to the backend, or NULL on failure.
 */
RAC_API rac_handle_t rac_diffusion_sdcpp_create(void);

/**
 * @brief Destroy a sd.cpp diffusion backend instance.
 * @param handle Backend handle from rac_diffusion_sdcpp_create().
 */
RAC_API void rac_diffusion_sdcpp_destroy(rac_handle_t handle);

// =============================================================================
// MODEL MANAGEMENT
// =============================================================================

/**
 * @brief Load a diffusion model.
 *
 * Accepts .safetensors, .gguf, or .ckpt model files.
 * On iOS uses Metal backend, on Android uses CPU/Vulkan/OpenCL.
 *
 * @param handle Backend handle.
 * @param model_path Path to the model file or directory.
 * @param config Configuration (variant, memory settings, etc.).
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_load_model(rac_handle_t handle, const char* model_path,
                                                     const rac_diffusion_config_t* config);

/**
 * @brief Unload the current model and free resources.
 * @param handle Backend handle.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_unload(rac_handle_t handle);

// =============================================================================
// GENERATION
// =============================================================================

/**
 * @brief Generate an image from a text prompt.
 *
 * @param handle Backend handle.
 * @param options Generation options (prompt, size, steps, etc.).
 * @param out_result Output result with RGBA image data.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_generate(rac_handle_t handle,
                                                   const rac_diffusion_options_t* options,
                                                   rac_diffusion_result_t* out_result);

/**
 * @brief Generate an image with progress reporting.
 *
 * @param handle Backend handle.
 * @param options Generation options.
 * @param progress_callback Called at each denoising step.
 * @param user_data User context passed to callback.
 * @param out_result Output result.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_generate_with_progress(
    rac_handle_t handle, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback, void* user_data,
    rac_diffusion_result_t* out_result);

/**
 * @brief Cancel an ongoing generation.
 * @param handle Backend handle.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_cancel(rac_handle_t handle);

// =============================================================================
// INFO
// =============================================================================

/**
 * @brief Get backend information.
 * @param handle Backend handle.
 * @param out_info Output info structure.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_diffusion_sdcpp_get_info(rac_handle_t handle,
                                                    rac_diffusion_info_t* out_info);

/**
 * @brief Get capability flags for this backend.
 * @param handle Backend handle.
 * @return Bitmask of RAC_DIFFUSION_CAP_* flags.
 */
RAC_API uint32_t rac_diffusion_sdcpp_get_capabilities(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * @brief Register the sd.cpp diffusion backend with the service registry.
 *
 * After registration, the service registry will route diffusion requests
 * to this backend when the model is in sd.cpp-compatible format.
 *
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_backend_sdcpp_register(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_SDCPP_H */
