/**
 * @file rac_diffusion_platform.h
 * @brief RunAnywhere Commons - Platform Diffusion Backend (Apple ml-stable-diffusion)
 *
 * C API for platform-native diffusion services. On Apple platforms, this uses
 * ml-stable-diffusion with Core ML. The actual implementation is in Swift,
 * with C++ providing the registration and callback infrastructure.
 *
 * This backend follows the same pattern as LlamaCPP and ONNX backends,
 * but delegates to Swift via function pointer callbacks since
 * ml-stable-diffusion is a Swift-only framework.
 */

#ifndef RAC_DIFFUSION_PLATFORM_H
#define RAC_DIFFUSION_PLATFORM_H

#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/** Opaque handle to platform diffusion service */
typedef struct rac_diffusion_platform* rac_diffusion_platform_handle_t;

/**
 * Platform diffusion configuration.
 * Passed during initialization.
 */
typedef struct rac_diffusion_platform_config {
    /** Model variant (SD 1.5, SDXL, etc.) */
    rac_diffusion_model_variant_t model_variant;

    /** Enable safety checker */
    rac_bool_t enable_safety_checker;

    /** Reduce memory mode */
    rac_bool_t reduce_memory;

    /** Compute units to use (0 = auto, 1 = CPU, 2 = GPU, 3 = Neural Engine) */
    int32_t compute_units;

    /** Reserved for future use */
    void* reserved;
} rac_diffusion_platform_config_t;

/**
 * Generation options for platform diffusion.
 */
typedef struct rac_diffusion_platform_options {
    /** Text prompt */
    const char* prompt;

    /** Negative prompt */
    const char* negative_prompt;

    /** Output width */
    int32_t width;

    /** Output height */
    int32_t height;

    /** Number of inference steps */
    int32_t steps;

    /** Guidance scale */
    float guidance_scale;

    /** Random seed (-1 for random) */
    int64_t seed;

    /** Scheduler type */
    rac_diffusion_scheduler_t scheduler;

    /** Reserved for future options */
    void* reserved;
} rac_diffusion_platform_options_t;

/**
 * Platform diffusion result.
 */
typedef struct rac_diffusion_platform_result {
    /** Image data (RGBA format, caller must free) */
    uint8_t* image_data;

    /** Image data size in bytes */
    size_t image_size;

    /** Image width */
    int32_t width;

    /** Image height */
    int32_t height;

    /** Seed used for generation */
    int64_t seed_used;

    /** Whether safety check was triggered */
    rac_bool_t safety_triggered;
} rac_diffusion_platform_result_t;

// =============================================================================
// SWIFT CALLBACK TYPES
// =============================================================================

/**
 * Callback to check if platform diffusion can handle a model ID.
 * Implemented in Swift.
 *
 * @param model_id Model identifier to check (can be NULL)
 * @param user_data User-provided context
 * @return RAC_TRUE if this backend can handle the model
 */
typedef rac_bool_t (*rac_platform_diffusion_can_handle_fn)(const char* model_id, void* user_data);

/**
 * Callback to create platform diffusion service.
 * Implemented in Swift.
 *
 * @param model_path Path to model directory
 * @param config Configuration options
 * @param user_data User-provided context
 * @return Handle to created service (Swift object pointer), or NULL on failure
 */
typedef rac_handle_t (*rac_platform_diffusion_create_fn)(
    const char* model_path, const rac_diffusion_platform_config_t* config, void* user_data);

/**
 * Callback to generate image.
 * Implemented in Swift.
 *
 * @param handle Service handle from create
 * @param options Generation options
 * @param out_result Output: Generated image result
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_platform_diffusion_generate_fn)(
    rac_handle_t handle, const rac_diffusion_platform_options_t* options,
    rac_diffusion_platform_result_t* out_result, void* user_data);

/**
 * Progress callback type for Swift.
 *
 * @param progress Progress value (0.0-1.0)
 * @param step Current step
 * @param total_steps Total steps
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to cancel
 */
typedef rac_bool_t (*rac_platform_diffusion_progress_fn)(float progress, int32_t step,
                                                         int32_t total_steps, void* user_data);

/**
 * Callback to generate image with progress.
 * Implemented in Swift.
 *
 * @param handle Service handle from create
 * @param options Generation options
 * @param progress_callback Progress callback
 * @param progress_user_data User data for progress callback
 * @param out_result Output: Generated image result
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_platform_diffusion_generate_with_progress_fn)(
    rac_handle_t handle, const rac_diffusion_platform_options_t* options,
    rac_platform_diffusion_progress_fn progress_callback, void* progress_user_data,
    rac_diffusion_platform_result_t* out_result, void* user_data);

/**
 * Callback to cancel generation.
 * Implemented in Swift.
 *
 * @param handle Service handle
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_platform_diffusion_cancel_fn)(rac_handle_t handle, void* user_data);

/**
 * Callback to destroy platform diffusion service.
 * Implemented in Swift.
 *
 * @param handle Service handle to destroy
 * @param user_data User-provided context
 */
typedef void (*rac_platform_diffusion_destroy_fn)(rac_handle_t handle, void* user_data);

/**
 * Swift callbacks for platform diffusion operations.
 */
typedef struct rac_platform_diffusion_callbacks {
    rac_platform_diffusion_can_handle_fn can_handle;
    rac_platform_diffusion_create_fn create;
    rac_platform_diffusion_generate_fn generate;
    rac_platform_diffusion_generate_with_progress_fn generate_with_progress;
    rac_platform_diffusion_cancel_fn cancel;
    rac_platform_diffusion_destroy_fn destroy;
    void* user_data;
} rac_platform_diffusion_callbacks_t;

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

/**
 * Sets the Swift callbacks for platform diffusion operations.
 * Must be called before using platform diffusion services.
 *
 * @param callbacks Callback functions (copied internally)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_platform_diffusion_set_callbacks(
    const rac_platform_diffusion_callbacks_t* callbacks);

/**
 * Gets the current Swift callbacks.
 *
 * @return Pointer to callbacks, or NULL if not set
 */
RAC_API const rac_platform_diffusion_callbacks_t* rac_platform_diffusion_get_callbacks(void);

/**
 * Checks if Swift callbacks are registered.
 *
 * @return RAC_TRUE if callbacks are available
 */
RAC_API rac_bool_t rac_platform_diffusion_is_available(void);

// =============================================================================
// SERVICE API
// =============================================================================

/**
 * Creates a platform diffusion service.
 *
 * @param model_path Path to Core ML model directory
 * @param config Configuration options (can be NULL for defaults)
 * @param out_handle Output: Service handle
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_diffusion_platform_create(const char* model_path,
                                                   const rac_diffusion_platform_config_t* config,
                                                   rac_diffusion_platform_handle_t* out_handle);

/**
 * Destroys a platform diffusion service.
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_diffusion_platform_destroy(rac_diffusion_platform_handle_t handle);

/**
 * Generates an image using platform diffusion.
 *
 * @param handle Service handle
 * @param options Generation options
 * @param out_result Output: Generated image
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_diffusion_platform_generate(
    rac_diffusion_platform_handle_t handle, const rac_diffusion_platform_options_t* options,
    rac_diffusion_platform_result_t* out_result);

/**
 * Generates an image with progress reporting.
 *
 * @param handle Service handle
 * @param options Generation options
 * @param progress_callback Progress callback
 * @param progress_user_data User data for progress callback
 * @param out_result Output: Generated image
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_diffusion_platform_generate_with_progress(
    rac_diffusion_platform_handle_t handle, const rac_diffusion_platform_options_t* options,
    rac_platform_diffusion_progress_fn progress_callback, void* progress_user_data,
    rac_diffusion_platform_result_t* out_result);

/**
 * Cancels ongoing generation.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_diffusion_platform_cancel(rac_diffusion_platform_handle_t handle);

/**
 * Frees a platform diffusion result.
 *
 * @param result Result to free
 */
RAC_API void rac_diffusion_platform_result_free(rac_diffusion_platform_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_PLATFORM_H */
