/**
 * @file rac_diffusion_model_registry.h
 * @brief Diffusion Model Registry - CoreML-based model definitions for iOS/macOS
 *
 * Provides a registry for diffusion models. Currently supports CoreML backend only
 * (iOS/macOS with Apple Neural Engine acceleration).
 *
 * Features:
 * - Type-safe model definitions (no magic strings)
 * - CoreML backend with ANE → GPU → CPU automatic fallback
 * - Strategy pattern for extensibility
 * - Tokenizer source configuration (SD 1.5, SD 2.x, SDXL)
 */

#ifndef RAC_DIFFUSION_MODEL_REGISTRY_H
#define RAC_DIFFUSION_MODEL_REGISTRY_H

#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// BACKEND AND PLATFORM TYPES
// =============================================================================

/**
 * @brief Supported inference backends for diffusion models
 *
 * Currently only CoreML is implemented for iOS/macOS.
 * Other backends are reserved for future expansion.
 */
typedef enum rac_diffusion_backend {
    RAC_DIFFUSION_BACKEND_ONNX = 0,      /**< ONNX Runtime (reserved for future) */
    RAC_DIFFUSION_BACKEND_COREML = 1,    /**< CoreML (iOS/macOS - currently supported) */
    RAC_DIFFUSION_BACKEND_TFLITE = 2,    /**< TensorFlow Lite (reserved for future) */
    RAC_DIFFUSION_BACKEND_AUTO = 99      /**< Auto-select (defaults to CoreML on Apple) */
} rac_diffusion_backend_t;

/**
 * @brief Platform availability flags (bitmask)
 *
 * Used to specify which platforms a model supports.
 */
typedef enum rac_diffusion_platform_flags {
    RAC_DIFFUSION_PLATFORM_NONE = 0,
    RAC_DIFFUSION_PLATFORM_IOS = (1 << 0),
    RAC_DIFFUSION_PLATFORM_ANDROID = (1 << 1),
    RAC_DIFFUSION_PLATFORM_MACOS = (1 << 2),
    RAC_DIFFUSION_PLATFORM_WINDOWS = (1 << 3),
    RAC_DIFFUSION_PLATFORM_LINUX = (1 << 4),
    RAC_DIFFUSION_PLATFORM_ALL = 0xFFFF
} rac_diffusion_platform_flags_t;

/**
 * @brief Hardware acceleration capabilities
 *
 * Describes what hardware the model can utilize.
 */
typedef enum rac_diffusion_hardware {
    RAC_DIFFUSION_HW_CPU = (1 << 0),     /**< CPU (always available) */
    RAC_DIFFUSION_HW_GPU = (1 << 1),     /**< GPU acceleration */
    RAC_DIFFUSION_HW_ANE = (1 << 2),     /**< Apple Neural Engine */
    RAC_DIFFUSION_HW_NPU = (1 << 3),     /**< Android NPU (Hexagon, etc.) */
    RAC_DIFFUSION_HW_DSP = (1 << 4),     /**< Android DSP */
} rac_diffusion_hardware_t;

// =============================================================================
// MODEL DEFINITION STRUCTURE
// =============================================================================

/**
 * @brief Default generation parameters for a model
 */
typedef struct rac_diffusion_model_defaults {
    int32_t width;                           /**< Default output width */
    int32_t height;                          /**< Default output height */
    int32_t steps;                           /**< Recommended inference steps */
    float guidance_scale;                    /**< CFG scale (0.0 for CFG-free models) */
    rac_diffusion_scheduler_t scheduler;     /**< Recommended scheduler */
    rac_bool_t requires_cfg;                 /**< True if model needs CFG (false for SDXS/Turbo) */
} rac_diffusion_model_defaults_t;

/**
 * @brief Download information for a model
 */
typedef struct rac_diffusion_model_download {
    const char* base_url;                    /**< HuggingFace URL or CDN */
    const char* onnx_path;                   /**< Path to ONNX files within repo */
    const char* coreml_path;                 /**< Path to CoreML files (if available) */
    uint64_t size_bytes;                     /**< Approximate download size */
    const char* checksum;                    /**< SHA256 checksum (optional) */
} rac_diffusion_model_download_t;

/**
 * @brief Tokenizer information for a model
 */
typedef struct rac_diffusion_model_tokenizer {
    rac_diffusion_tokenizer_source_t source; /**< Tokenizer type */
    const char* custom_url;                  /**< For custom tokenizers */
} rac_diffusion_model_tokenizer_t;

/**
 * @brief Complete diffusion model definition
 *
 * Contains all metadata needed to download, load, and use a model.
 * This structure is shared across all SDKs via the C++ commons layer.
 *
 * ## Adding a New Model
 *
 * To add a new diffusion model:
 * 1. Add a new `rac_diffusion_model_def_t` in `diffusion_model_registry.cpp`
 * 2. Include it in the `BUILTIN_MODELS` array
 * 3. Set the appropriate tokenizer source (SD15, SD2, SDXL, or CUSTOM)
 *
 * Example:
 * @code
 * static const rac_diffusion_model_def_t MY_MODEL = {
 *     .model_id = "my-model-onnx",
 *     .display_name = "My Custom Model",
 *     .description = "Description here",
 *     .variant = RAC_DIFFUSION_MODEL_SD_1_5,
 *     .backend = RAC_DIFFUSION_BACKEND_ONNX,
 *     .platforms = RAC_DIFFUSION_PLATFORM_ALL,
 *     .hardware = RAC_DIFFUSION_HW_CPU | RAC_DIFFUSION_HW_GPU,
 *     .defaults = { .width = 512, .height = 512, .steps = 20, ... },
 *     .download = {
 *         .base_url = "https://huggingface.co/my-org/my-model",
 *         .onnx_path = "onnx",
 *         .size_bytes = 2000000000ULL,
 *     },
 *     .tokenizer = {
 *         .source = RAC_DIFFUSION_TOKENIZER_SD_1_5,  // Reuse existing tokenizer
 *     },
 * };
 * @endcode
 */
typedef struct rac_diffusion_model_def {
    /** Unique model identifier (e.g., "sdxs-512-0.9-onnx") */
    const char* model_id;
    
    /** Human-readable name */
    const char* display_name;
    
    /** Description */
    const char* description;
    
    /** Model variant (SD 1.5, SDXL, SDXS, LCM, etc.) */
    rac_diffusion_model_variant_t variant;
    
    /** Preferred backend for this model */
    rac_diffusion_backend_t backend;
    
    /** Platform availability (bitmask of rac_diffusion_platform_t) */
    uint32_t platforms;
    
    /** Hardware capabilities (bitmask of rac_diffusion_hardware_t) */
    uint32_t hardware;
    
    /** Default generation parameters */
    rac_diffusion_model_defaults_t defaults;
    
    /** Download information */
    rac_diffusion_model_download_t download;
    
    /** Tokenizer information */
    rac_diffusion_model_tokenizer_t tokenizer;
    
    /** Model-specific flags */
    rac_bool_t is_recommended;               /**< Show as recommended in UI */
    rac_bool_t supports_img2img;             /**< Supports image-to-image */
    rac_bool_t supports_inpainting;          /**< Supports inpainting */
    
} rac_diffusion_model_def_t;

// =============================================================================
// MODEL STRATEGY INTERFACE
// =============================================================================

/**
 * @brief Model strategy - allows custom model handling
 *
 * Contributors implement this interface to add support for new model types
 * without modifying core SDK code.
 *
 * Example:
 * @code
 * static rac_bool_t my_can_handle(const char* model_id, void* user_data) {
 *     return strcmp(model_id, "my-custom-model") == 0 ? RAC_TRUE : RAC_FALSE;
 * }
 *
 * static rac_result_t my_get_model_def(const char* model_id,
 *                                       rac_diffusion_model_def_t* out_def,
 *                                       void* user_data) {
 *     if (strcmp(model_id, "my-custom-model") == 0) {
 *         *out_def = MY_CUSTOM_MODEL_DEF;
 *         return RAC_SUCCESS;
 *     }
 *     return RAC_ERROR_NOT_FOUND;
 * }
 *
 * void register_my_models(void) {
 *     static rac_diffusion_model_strategy_t strategy = {
 *         .name = "MyModels",
 *         .can_handle = my_can_handle,
 *         .get_model_def = my_get_model_def,
 *         // ...
 *     };
 *     rac_diffusion_model_registry_register(&strategy);
 * }
 * @endcode
 */
typedef struct rac_diffusion_model_strategy {
    /** Strategy name (e.g., "SDXS", "LCM", "CustomModel") */
    const char* name;
    
    /** Check if this strategy can handle a model ID */
    rac_bool_t (*can_handle)(const char* model_id, void* user_data);
    
    /** Get model definition for a model ID */
    rac_result_t (*get_model_def)(const char* model_id, 
                                   rac_diffusion_model_def_t* out_def,
                                   void* user_data);
    
    /** Get all models supported by this strategy */
    rac_result_t (*list_models)(rac_diffusion_model_def_t** out_models,
                                 size_t* out_count,
                                 void* user_data);
    
    /** Select best backend for current platform */
    rac_diffusion_backend_t (*select_backend)(const rac_diffusion_model_def_t* model,
                                               void* user_data);
    
    /** Optional: Custom model loading (if default isn't suitable) */
    rac_result_t (*load_model)(const char* model_path,
                                const rac_diffusion_model_def_t* model_def,
                                rac_handle_t* out_service,
                                void* user_data);
    
    /** User data passed to callbacks */
    void* user_data;
    
} rac_diffusion_model_strategy_t;

// =============================================================================
// REGISTRY API
// =============================================================================

/**
 * @brief Initialize the diffusion model registry
 *
 * Registers built-in model strategies (SD 1.5, SDXS, LCM, etc.)
 * Must be called during SDK initialization.
 */
RAC_API void rac_diffusion_model_registry_init(void);

/**
 * @brief Cleanup the diffusion model registry
 */
RAC_API void rac_diffusion_model_registry_cleanup(void);

/**
 * @brief Register a model strategy
 *
 * @param strategy Strategy to register (caller retains ownership)
 * @return RAC_SUCCESS on success, RAC_ERROR_ALREADY_EXISTS if name taken
 */
RAC_API rac_result_t rac_diffusion_model_registry_register(
    const rac_diffusion_model_strategy_t* strategy);

/**
 * @brief Unregister a model strategy
 *
 * @param name Strategy name to unregister
 * @return RAC_SUCCESS on success, RAC_ERROR_NOT_FOUND if not registered
 */
RAC_API rac_result_t rac_diffusion_model_registry_unregister(const char* name);

/**
 * @brief Get model definition by ID
 *
 * @param model_id Model identifier
 * @param out_def Output model definition (filled on success)
 * @return RAC_SUCCESS if found, RAC_ERROR_NOT_FOUND otherwise
 */
RAC_API rac_result_t rac_diffusion_model_registry_get(
    const char* model_id,
    rac_diffusion_model_def_t* out_def);

/**
 * @brief List all available models for current platform
 *
 * @param out_models Output array (caller must free with free())
 * @param out_count Number of models
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_diffusion_model_registry_list(
    rac_diffusion_model_def_t** out_models,
    size_t* out_count);

/**
 * @brief Select best backend for a model on current platform
 *
 * This function implements the fallback chain:
 * - iOS/macOS: CoreML (ANE → GPU → CPU automatic via CoreML)
 * - Android: ONNX with NNAPI EP (NPU → DSP → GPU → CPU automatic via NNAPI)
 * - Desktop: ONNX with CPU EP
 *
 * @param model_id Model identifier
 * @return Best backend, or RAC_DIFFUSION_BACKEND_ONNX as fallback
 */
RAC_API rac_diffusion_backend_t rac_diffusion_model_registry_select_backend(
    const char* model_id);

/**
 * @brief Check if a model is available on current platform
 *
 * @param model_id Model identifier
 * @return RAC_TRUE if available, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_diffusion_model_registry_is_available(const char* model_id);

/**
 * @brief Get recommended model for current platform
 *
 * Returns the model marked as is_recommended=true that's available on
 * the current platform.
 *
 * @param out_def Output model definition (filled on success)
 * @return RAC_SUCCESS if found, RAC_ERROR_NOT_FOUND if no recommendation
 */
RAC_API rac_result_t rac_diffusion_model_registry_get_recommended(
    rac_diffusion_model_def_t* out_def);

/**
 * @brief Get current platform flags
 *
 * @return Bitmask of current platform (e.g., RAC_DIFFUSION_PLATFORM_IOS)
 */
RAC_API uint32_t rac_diffusion_model_registry_get_current_platform(void);

/**
 * @brief Check if model variant requires CFG (classifier-free guidance)
 *
 * SDXS, SDXL Turbo, and similar distilled models don't need CFG.
 *
 * @param variant Model variant
 * @return RAC_TRUE if CFG is required, RAC_FALSE for CFG-free models
 */
RAC_API rac_bool_t rac_diffusion_model_requires_cfg(rac_diffusion_model_variant_t variant);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_MODEL_REGISTRY_H */
