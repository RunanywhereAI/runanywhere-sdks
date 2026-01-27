/**
 * @file rac_vlm_service.h
 * @brief RunAnywhere Commons - VLM Service Interface
 *
 * Defines the generic VLM service API and vtable for multi-backend dispatch.
 * Backends (LlamaCpp VLM, MLX VLM) implement the vtable and register
 * with the service registry.
 */

#ifndef RAC_VLM_SERVICE_H
#define RAC_VLM_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/vlm/rac_vlm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * VLM Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_vlm_service_ops {
    /**
     * Initialize the service with model path(s).
     * @param impl Backend implementation handle
     * @param model_path Path to the main model file (LLM weights)
     * @param mmproj_path Path to vision projector (required for llama.cpp, NULL for MLX)
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*initialize)(void* impl, const char* model_path, const char* mmproj_path);

    /**
     * Process an image with a text prompt (blocking).
     * @param impl Backend implementation handle
     * @param image Image input
     * @param prompt Text prompt
     * @param options Generation options (can be NULL for defaults)
     * @param out_result Output result (caller must free with rac_vlm_result_free)
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*process)(void* impl, const rac_vlm_image_t* image, const char* prompt,
                            const rac_vlm_options_t* options, rac_vlm_result_t* out_result);

    /**
     * Process an image with streaming callback.
     * @param impl Backend implementation handle
     * @param image Image input
     * @param prompt Text prompt
     * @param options Generation options (can be NULL for defaults)
     * @param callback Token callback
     * @param user_data User context for callback
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*process_stream)(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                   const rac_vlm_options_t* options,
                                   rac_vlm_stream_callback_fn callback, void* user_data);

    /**
     * Get service information.
     * @param impl Backend implementation handle
     * @param out_info Output info structure
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*get_info)(void* impl, rac_vlm_info_t* out_info);

    /**
     * Cancel ongoing generation.
     * @param impl Backend implementation handle
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*cancel)(void* impl);

    /**
     * Cleanup/unload model (keeps service alive).
     * @param impl Backend implementation handle
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*cleanup)(void* impl);

    /**
     * Destroy the service.
     * @param impl Backend implementation handle
     */
    void (*destroy)(void* impl);
} rac_vlm_service_ops_t;

/**
 * VLM Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_vlm_service {
    /** Vtable with backend operations */
    const rac_vlm_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_vlm_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create a VLM service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_id Model identifier (registry ID or path to model file)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_create(const char* model_id, rac_handle_t* out_handle);

/**
 * @brief Initialize a VLM service with model paths
 *
 * @param handle Service handle
 * @param model_path Path to the main model file
 * @param mmproj_path Path to vision projector (can be NULL for some backends)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_initialize(rac_handle_t handle, const char* model_path,
                                        const char* mmproj_path);

/**
 * @brief Process an image with a text prompt
 *
 * @param handle Service handle
 * @param image Image input
 * @param prompt Text prompt describing what to analyze
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free with rac_vlm_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                     const char* prompt, const rac_vlm_options_t* options,
                                     rac_vlm_result_t* out_result);

/**
 * @brief Process an image with streaming response
 *
 * @param handle Service handle
 * @param image Image input
 * @param prompt Text prompt
 * @param options Generation options (can be NULL for defaults)
 * @param callback Callback for each generated token
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                            const char* prompt, const rac_vlm_options_t* options,
                                            rac_vlm_stream_callback_fn callback, void* user_data);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_get_info(rac_handle_t handle, rac_vlm_info_t* out_info);

/**
 * @brief Cancel ongoing generation
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_cancel(rac_handle_t handle);

/**
 * @brief Cleanup and release model resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_cleanup(rac_handle_t handle);

/**
 * @brief Destroy a VLM service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_vlm_destroy(rac_handle_t handle);

/**
 * @brief Free a VLM result
 *
 * @param result Result to free
 */
RAC_API void rac_vlm_result_free(rac_vlm_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_SERVICE_H */
