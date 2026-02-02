/**
 * @file rac_diffusion_onnx.h
 * @brief RunAnywhere Core - ONNX Backend RAC API for Diffusion
 *
 * Direct RAC API for ONNX-based Stable Diffusion inference.
 * Supports SD 1.5, SD 2.x, and SDXL models in ONNX format.
 *
 * This backend provides cross-platform diffusion support using ONNX Runtime
 * with platform-specific execution providers (CoreML, NNAPI, CUDA, CPU).
 */

#ifndef RAC_DIFFUSION_ONNX_H
#define RAC_DIFFUSION_ONNX_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_ONNX_BUILDING)
#if defined(_WIN32)
#define RAC_ONNX_DIFFUSION_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_ONNX_DIFFUSION_API __attribute__((visibility("default")))
#else
#define RAC_ONNX_DIFFUSION_API
#endif
#else
#define RAC_ONNX_DIFFUSION_API
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief ONNX Execution Provider selection
 */
typedef enum rac_diffusion_onnx_ep {
    RAC_DIFFUSION_ONNX_EP_AUTO = 0,      /**< Auto-detect best provider */
    RAC_DIFFUSION_ONNX_EP_CPU = 1,       /**< CPU only */
    RAC_DIFFUSION_ONNX_EP_COREML = 2,    /**< Apple CoreML (Neural Engine) */
    RAC_DIFFUSION_ONNX_EP_NNAPI = 3,     /**< Android NNAPI */
    RAC_DIFFUSION_ONNX_EP_CUDA = 4,      /**< NVIDIA CUDA */
    RAC_DIFFUSION_ONNX_EP_DIRECTML = 5,  /**< Windows DirectML */
} rac_diffusion_onnx_ep_t;

/**
 * @brief ONNX Diffusion configuration
 */
typedef struct rac_diffusion_onnx_config {
    rac_diffusion_model_variant_t model_variant;
    rac_diffusion_scheduler_t scheduler;
    rac_diffusion_onnx_ep_t execution_provider;
    int32_t num_threads;               /**< 0 = auto */
    rac_bool_t enable_memory_pattern;  /**< Enable memory optimization */
    rac_bool_t enable_cpu_mem_arena;   /**< Enable CPU memory arena */
} rac_diffusion_onnx_config_t;

/**
 * @brief Default ONNX diffusion configuration
 */
static const rac_diffusion_onnx_config_t RAC_DIFFUSION_ONNX_CONFIG_DEFAULT = {
    .model_variant = RAC_DIFFUSION_MODEL_SD_1_5,
    .scheduler = RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS,
    .execution_provider = RAC_DIFFUSION_ONNX_EP_AUTO,
    .num_threads = 0,
    .enable_memory_pattern = RAC_TRUE,
    .enable_cpu_mem_arena = RAC_TRUE,
};

// =============================================================================
// ONNX DIFFUSION API
// =============================================================================

/**
 * @brief Create ONNX diffusion handle
 *
 * @param model_path Path to model directory containing ONNX files
 * @param config Configuration options (NULL for defaults)
 * @param out_handle Output handle
 * @return RAC_OK on success
 */
RAC_ONNX_DIFFUSION_API rac_result_t rac_diffusion_onnx_create(
    const char* model_path,
    const rac_diffusion_onnx_config_t* config,
    rac_handle_t* out_handle);

/**
 * @brief Generate image from text prompt
 *
 * @param handle Diffusion handle
 * @param options Generation options
 * @param out_result Output result (caller must call rac_diffusion_onnx_result_free)
 * @return RAC_OK on success
 */
RAC_ONNX_DIFFUSION_API rac_result_t rac_diffusion_onnx_generate(
    rac_handle_t handle,
    const rac_diffusion_options_t* options,
    rac_diffusion_result_t* out_result);

/**
 * @brief Generate image with progress callback
 *
 * @param handle Diffusion handle
 * @param options Generation options
 * @param progress_callback Callback for progress updates (return RAC_FALSE to cancel)
 * @param user_data User data passed to callback
 * @param out_result Output result
 * @return RAC_OK on success
 */
RAC_ONNX_DIFFUSION_API rac_result_t rac_diffusion_onnx_generate_with_progress(
    rac_handle_t handle,
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback,
    void* user_data,
    rac_diffusion_result_t* out_result);

/**
 * @brief Cancel ongoing generation
 *
 * @param handle Diffusion handle
 * @return RAC_OK on success
 */
RAC_ONNX_DIFFUSION_API rac_result_t rac_diffusion_onnx_cancel(rac_handle_t handle);

/**
 * @brief Get model information
 *
 * @param handle Diffusion handle
 * @param out_info Output info struct
 * @return RAC_OK on success
 */
RAC_ONNX_DIFFUSION_API rac_result_t rac_diffusion_onnx_get_info(
    rac_handle_t handle,
    rac_diffusion_info_t* out_info);

/**
 * @brief Get supported capabilities
 *
 * @param handle Diffusion handle
 * @return Bitmask of RAC_DIFFUSION_CAP_* flags
 */
RAC_ONNX_DIFFUSION_API uint32_t rac_diffusion_onnx_get_capabilities(rac_handle_t handle);

/**
 * @brief Check if model is loaded and ready
 *
 * @param handle Diffusion handle
 * @return RAC_TRUE if ready
 */
RAC_ONNX_DIFFUSION_API rac_bool_t rac_diffusion_onnx_is_ready(rac_handle_t handle);

/**
 * @brief Free result resources
 *
 * @param result Result to free
 */
RAC_ONNX_DIFFUSION_API void rac_diffusion_onnx_result_free(rac_diffusion_result_t* result);

/**
 * @brief Destroy diffusion handle
 *
 * @param handle Handle to destroy
 */
RAC_ONNX_DIFFUSION_API void rac_diffusion_onnx_destroy(rac_handle_t handle);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * @brief Check if a model directory contains ONNX diffusion models
 *
 * @param model_path Path to check
 * @return RAC_TRUE if directory contains valid ONNX diffusion models
 */
RAC_ONNX_DIFFUSION_API rac_bool_t rac_diffusion_onnx_is_valid_model(const char* model_path);

/**
 * @brief Get list of required ONNX files for a model
 *
 * @param model_variant Model variant
 * @param out_files Array to receive file paths (caller allocates)
 * @param max_files Maximum number of files to return
 * @return Number of required files
 */
RAC_ONNX_DIFFUSION_API int rac_diffusion_onnx_get_required_files(
    rac_diffusion_model_variant_t model_variant,
    const char** out_files,
    int max_files);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_ONNX_H */
