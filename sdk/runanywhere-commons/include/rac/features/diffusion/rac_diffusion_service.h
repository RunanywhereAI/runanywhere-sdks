/**
 * @file rac_diffusion_service.h
 * @brief RunAnywhere Commons - Diffusion Service Interface
 *
 * Defines the generic diffusion service API and vtable for multi-backend dispatch.
 * Backends (CoreML, ONNX, Platform) implement the vtable and register
 * with the service registry.
 */

#ifndef RAC_DIFFUSION_SERVICE_H
#define RAC_DIFFUSION_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/diffusion/rac_diffusion_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * Diffusion Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_diffusion_service_ops {
    /** Initialize the service with a model path */
    rac_result_t (*initialize)(void* impl, const char* model_path,
                               const rac_diffusion_config_t* config);

    /** Generate image (blocking) */
    rac_result_t (*generate)(void* impl, const rac_diffusion_options_t* options,
                             rac_diffusion_result_t* out_result);

    /** Generate image with progress callback */
    rac_result_t (*generate_with_progress)(void* impl, const rac_diffusion_options_t* options,
                                           rac_diffusion_progress_callback_fn progress_callback,
                                           void* user_data, rac_diffusion_result_t* out_result);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_diffusion_info_t* out_info);

    /** Get supported capabilities as bitmask */
    uint32_t (*get_capabilities)(void* impl);

    /** Cancel ongoing generation */
    rac_result_t (*cancel)(void* impl);

    /** Cleanup/unload model (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);

    /**
     * Allocate a backend-specific impl for a new diffusion service.
     * v3 replacement for the legacy rac_service_provider_t::create callback.
     * See rac_llm_service_ops_t::create for the full semantics.
     */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_diffusion_service_ops_t;

/**
 * Diffusion Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_diffusion_service {
    /** Vtable with backend operations */
    const rac_diffusion_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_diffusion_service_t;

/**
 * @brief Callback for serialized runanywhere.v1.DiffusionProgress bytes.
 */
typedef rac_bool_t (*rac_diffusion_progress_proto_callback_fn)(
    const uint8_t* progress_proto_bytes, size_t progress_proto_size, void* user_data);

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create a diffusion service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_id Model identifier (registry ID or path to model)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_create(const char* model_id, rac_handle_t* out_handle);

/**
 * @brief Create a diffusion service with configuration
 *
 * Routes through service registry to find appropriate backend, honoring
 * configuration hints such as preferred framework when provided.
 *
 * @param model_id Model identifier (registry ID or path to model)
 * @param config Optional configuration (can be NULL)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_create_with_config(const char* model_id,
                                                      const rac_diffusion_config_t* config,
                                                      rac_handle_t* out_handle);

/**
 * @brief Initialize a diffusion service
 *
 * @param handle Service handle
 * @param model_path Path to the model directory
 * @param config Configuration (can be NULL for defaults)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_initialize(rac_handle_t handle, const char* model_path,
                                              const rac_diffusion_config_t* config);

/**
 * @brief Generate an image from prompt
 *
 * Blocking call that generates an image.
 *
 * @param handle Service handle
 * @param options Generation options
 * @param out_result Output: Generation result (caller must free with rac_diffusion_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_generate(rac_handle_t handle,
                                            const rac_diffusion_options_t* options,
                                            rac_diffusion_result_t* out_result);

/**
 * @brief Generate an image from serialized runanywhere.v1.DiffusionGenerationOptions.
 *
 * out_result receives serialized runanywhere.v1.DiffusionResult bytes.
 */
RAC_API rac_result_t rac_diffusion_generate_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_proto_buffer_t* out_result);

/**
 * @brief Generate an image with progress reporting
 *
 * @param handle Service handle
 * @param options Generation options
 * @param progress_callback Callback for progress updates
 * @param user_data User context passed to callback
 * @param out_result Output: Generation result (caller must free with rac_diffusion_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t
rac_diffusion_generate_with_progress(rac_handle_t handle, const rac_diffusion_options_t* options,
                                     rac_diffusion_progress_callback_fn progress_callback,
                                     void* user_data, rac_diffusion_result_t* out_result);

/**
 * @brief Generate an image with serialized progress callbacks.
 *
 * options_proto_bytes encodes runanywhere.v1.DiffusionGenerationOptions.
 * progress_callback receives serialized runanywhere.v1.DiffusionProgress bytes.
 * out_result receives serialized runanywhere.v1.DiffusionResult bytes.
 */
RAC_API rac_result_t rac_diffusion_generate_with_progress_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_diffusion_progress_proto_callback_fn progress_callback, void* user_data,
    rac_proto_buffer_t* out_result);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_get_info(rac_handle_t handle, rac_diffusion_info_t* out_info);

/**
 * @brief Get supported capabilities as bitmask
 *
 * @param handle Service handle
 * @return Capability bitmask (RAC_DIFFUSION_CAP_* flags)
 */
RAC_API uint32_t rac_diffusion_get_capabilities(rac_handle_t handle);

/**
 * @brief Cancel ongoing generation
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_cancel(rac_handle_t handle);

/**
 * @brief Cancel diffusion generation and emit canonical cancellation events.
 */
RAC_API rac_result_t rac_diffusion_cancel_proto(rac_handle_t handle);

/**
 * @brief Cleanup and release model resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_cleanup(rac_handle_t handle);

/**
 * @brief Destroy a diffusion service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_diffusion_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_SERVICE_H */
