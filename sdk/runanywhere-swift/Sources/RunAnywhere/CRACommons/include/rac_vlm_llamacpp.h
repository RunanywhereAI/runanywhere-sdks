/**
 * @file rac_vlm_llamacpp.h
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend API
 *
 * Public C API for Vision Language Model inference using llama.cpp's
 * multimodal (mtmd) capabilities. Supports 20+ VLM architectures including
 * Qwen2-VL, Qwen2.5-VL, SmolVLM, LLaVA, MiniCPM-V, and more.
 */

#ifndef RAC_VLM_LLAMACPP_H
#define RAC_VLM_LLAMACPP_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_vlm.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_LLAMACPP_BUILDING)
#if defined(_WIN32)
#define RAC_LLAMACPP_VLM_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_LLAMACPP_VLM_API __attribute__((visibility("default")))
#else
#define RAC_LLAMACPP_VLM_API
#endif
#else
#define RAC_LLAMACPP_VLM_API
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * LlamaCPP VLM-specific configuration.
 */
typedef struct rac_vlm_llamacpp_config {
    /** Context size (0 = auto-detect from model) */
    int32_t context_size;

    /** Number of threads for CPU inference (0 = auto-detect) */
    int32_t num_threads;

    /** Number of layers to offload to GPU (Metal on iOS/macOS, -1 = all) */
    int32_t gpu_layers;

    /** Batch size for prompt processing */
    int32_t batch_size;

    /** Number of threads for vision encoder (0 = same as num_threads) */
    int32_t vision_threads;

    /** Use GPU for vision encoding */
    rac_bool_t use_gpu_vision;
} rac_vlm_llamacpp_config_t;

/**
 * Default LlamaCPP VLM configuration.
 */
static const rac_vlm_llamacpp_config_t RAC_VLM_LLAMACPP_CONFIG_DEFAULT = {
    .context_size = 0,      // Auto-detect
    .num_threads = 0,       // Auto-detect
    .gpu_layers = -1,       // All layers on GPU
    .batch_size = 512,      //
    .vision_threads = 0,    // Auto-detect
    .use_gpu_vision = 1     // Use GPU for vision
};

// =============================================================================
// LLAMACPP VLM-SPECIFIC API
// =============================================================================

/**
 * Creates a LlamaCPP VLM service.
 *
 * @param model_path Path to the GGUF LLM model file
 * @param mmproj_path Path to the mmproj vision projector GGUF file
 * @param config LlamaCPP-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_create(const char* model_path,
                                                          const char* mmproj_path,
                                                          const rac_vlm_llamacpp_config_t* config,
                                                          rac_handle_t* out_handle);

/**
 * Loads a VLM model into an existing service.
 *
 * @param handle Service handle
 * @param model_path Path to the GGUF LLM model file
 * @param mmproj_path Path to the mmproj vision projector GGUF file
 * @param config LlamaCPP configuration (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_load_model(
    rac_handle_t handle, const char* model_path, const char* mmproj_path,
    const rac_vlm_llamacpp_config_t* config);

/**
 * Unloads the current model.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_unload_model(rac_handle_t handle);

/**
 * Checks if a model is loaded.
 *
 * @param handle Service handle
 * @return RAC_TRUE if model is loaded, RAC_FALSE otherwise
 */
RAC_LLAMACPP_VLM_API rac_bool_t rac_vlm_llamacpp_is_model_loaded(rac_handle_t handle);

/**
 * Processes an image with a text prompt (blocking).
 *
 * @param handle Service handle
 * @param image Image input (file path, RGB pixels, or base64)
 * @param prompt Text prompt
 * @param options VLM generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free text with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_process(rac_handle_t handle,
                                                           const rac_vlm_image_t* image,
                                                           const char* prompt,
                                                           const rac_vlm_options_t* options,
                                                           rac_vlm_result_t* out_result);

/**
 * Streaming callback for VLM generation.
 *
 * @param token Generated token string
 * @param is_final Whether this is the final token
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop
 */
typedef rac_bool_t (*rac_vlm_llamacpp_stream_callback_fn)(const char* token, rac_bool_t is_final,
                                                          void* user_data);

/**
 * Processes an image with streaming callback.
 *
 * @param handle Service handle
 * @param image Image input
 * @param prompt Text prompt
 * @param options VLM generation options
 * @param callback Callback for each token
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_process_stream(
    rac_handle_t handle, const rac_vlm_image_t* image, const char* prompt,
    const rac_vlm_options_t* options, rac_vlm_llamacpp_stream_callback_fn callback, void* user_data);

/**
 * Cancels ongoing generation.
 *
 * @param handle Service handle
 */
RAC_LLAMACPP_VLM_API void rac_vlm_llamacpp_cancel(rac_handle_t handle);

/**
 * Gets model information as JSON.
 *
 * @param handle Service handle
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_vlm_llamacpp_get_model_info(rac_handle_t handle,
                                                                  char** out_json);

/**
 * Destroys a LlamaCPP VLM service.
 *
 * @param handle Service handle to destroy
 */
RAC_LLAMACPP_VLM_API void rac_vlm_llamacpp_destroy(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the LlamaCPP VLM backend with the commons module and service registries.
 *
 * Should be called once during SDK initialization.
 * This registers:
 * - Module: "llamacpp_vlm" with VISION_LANGUAGE capability
 * - Service provider: LlamaCPP VLM provider (priority 100)
 *
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_backend_llamacpp_vlm_register(void);

/**
 * Unregisters the LlamaCPP VLM backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_VLM_API rac_result_t rac_backend_llamacpp_vlm_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_LLAMACPP_H */
