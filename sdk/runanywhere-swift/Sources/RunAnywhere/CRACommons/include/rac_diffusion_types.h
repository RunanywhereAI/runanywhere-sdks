/**
 * @file rac_diffusion_types.h
 * @brief RunAnywhere Commons - Diffusion Types and Data Structures
 *
 * This header defines data structures for image generation using diffusion models
 * (Stable Diffusion). Supports text-to-image, image-to-image, and inpainting.
 *
 * This header defines data structures only. For the service interface,
 * see rac_diffusion_service.h.
 */

#ifndef RAC_DIFFUSION_TYPES_H
#define RAC_DIFFUSION_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SCHEDULER TYPES
// =============================================================================

/**
 * @brief Diffusion scheduler/sampler types
 *
 * Different scheduling algorithms for the denoising process.
 * DPM++ 2M Karras is recommended for best quality/speed tradeoff.
 */
typedef enum rac_diffusion_scheduler {
    RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS = 0, /**< DPM++ 2M Karras (recommended) */
    RAC_DIFFUSION_SCHEDULER_DPM_PP_2M = 1,        /**< DPM++ 2M */
    RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE = 2,    /**< DPM++ 2M SDE */
    RAC_DIFFUSION_SCHEDULER_DDIM = 3,             /**< DDIM */
    RAC_DIFFUSION_SCHEDULER_EULER = 4,            /**< Euler */
    RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL = 5,  /**< Euler Ancestral */
    RAC_DIFFUSION_SCHEDULER_PNDM = 6,             /**< PNDM */
    RAC_DIFFUSION_SCHEDULER_LMS = 7,              /**< LMS */
} rac_diffusion_scheduler_t;

/**
 * @brief Model variant types
 *
 * Different Stable Diffusion model variants with different capabilities.
 */
typedef enum rac_diffusion_model_variant {
    RAC_DIFFUSION_MODEL_SD_1_5 = 0,   /**< Stable Diffusion 1.5 (512x512 default) */
    RAC_DIFFUSION_MODEL_SD_2_1 = 1,   /**< Stable Diffusion 2.1 (768x768 default) */
    RAC_DIFFUSION_MODEL_SDXL = 2,     /**< SDXL (1024x1024 default, requires 8GB+ RAM) */
    RAC_DIFFUSION_MODEL_SDXL_TURBO = 3, /**< SDXL Turbo (fast, fewer steps) */
} rac_diffusion_model_variant_t;

/**
 * @brief Generation mode
 */
typedef enum rac_diffusion_mode {
    RAC_DIFFUSION_MODE_TEXT_TO_IMAGE = 0, /**< Generate image from text prompt */
    RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE = 1, /**< Transform input image with prompt */
    RAC_DIFFUSION_MODE_INPAINTING = 2,     /**< Edit specific regions with mask */
} rac_diffusion_mode_t;

// =============================================================================
// TOKENIZER CONFIGURATION
// =============================================================================

/**
 * @brief Tokenizer source presets
 *
 * Predefined HuggingFace repository sources for tokenizer files.
 * Apple's compiled CoreML models don't include tokenizer files (vocab.json, merges.txt),
 * so they must be downloaded separately from HuggingFace.
 *
 * Developers can use RAC_DIFFUSION_TOKENIZER_CUSTOM with a custom_base_url
 * to specify their own tokenizer source.
 */
typedef enum rac_diffusion_tokenizer_source {
    /** Stable Diffusion 1.x tokenizer (CLIP ViT-L/14)
     *  Source: runwayml/stable-diffusion-v1-5 */
    RAC_DIFFUSION_TOKENIZER_SD_1_5 = 0,

    /** Stable Diffusion 2.x tokenizer (OpenCLIP ViT-H/14)
     *  Source: stabilityai/stable-diffusion-2-1 */
    RAC_DIFFUSION_TOKENIZER_SD_2_X = 1,

    /** Stable Diffusion XL tokenizer (dual tokenizers)
     *  Source: stabilityai/stable-diffusion-xl-base-1.0 */
    RAC_DIFFUSION_TOKENIZER_SDXL = 2,

    /** Custom tokenizer from a developer-specified URL
     *  Requires custom_base_url to be set in rac_diffusion_tokenizer_config_t */
    RAC_DIFFUSION_TOKENIZER_CUSTOM = 99,
} rac_diffusion_tokenizer_source_t;

/**
 * @brief Tokenizer configuration
 *
 * Configuration for downloading and using tokenizer files.
 * The SDK will automatically download missing tokenizer files (vocab.json, merges.txt)
 * from the specified source URL.
 *
 * Example for custom URL:
 * @code
 * rac_diffusion_tokenizer_config_t tokenizer_config = {
 *     .source = RAC_DIFFUSION_TOKENIZER_CUSTOM,
 *     .custom_base_url = "https://huggingface.co/my-org/my-model/resolve/main/tokenizer",
 *     .auto_download = RAC_TRUE
 * };
 * @endcode
 */
typedef struct rac_diffusion_tokenizer_config {
    /** Tokenizer source preset (SD15, SD21, SDXL, or CUSTOM) */
    rac_diffusion_tokenizer_source_t source;

    /** Custom base URL for tokenizer files (only used when source == CUSTOM)
     *  Should be a URL directory containing vocab.json and merges.txt
     *  Example: "https://huggingface.co/my-org/my-model/resolve/main/tokenizer"
     *  The SDK will append "/vocab.json" and "/merges.txt" to download files */
    const char* custom_base_url;

    /** Automatically download missing tokenizer files (default: true) */
    rac_bool_t auto_download;
} rac_diffusion_tokenizer_config_t;

/**
 * @brief Default tokenizer configuration
 */
static const rac_diffusion_tokenizer_config_t RAC_DIFFUSION_TOKENIZER_CONFIG_DEFAULT = {
    .source = RAC_DIFFUSION_TOKENIZER_SD_1_5,
    .custom_base_url = RAC_NULL,
    .auto_download = RAC_TRUE};

// =============================================================================
// CONFIGURATION - Component configuration
// =============================================================================

/**
 * @brief Diffusion component configuration
 *
 * Configuration for initializing the diffusion component.
 */
typedef struct rac_diffusion_config {
    /** Model ID (optional - uses default if NULL) */
    const char* model_id;

    /** Preferred framework (use RAC_FRAMEWORK_UNKNOWN for auto) */
    int32_t preferred_framework;

    /** Model variant (SD 1.5, SD 2.1, SDXL, etc.) */
    rac_diffusion_model_variant_t model_variant;

    /** Enable safety checker for NSFW content filtering (default: true) */
    rac_bool_t enable_safety_checker;

    /** Reduce memory footprint (may reduce quality, default: false) */
    rac_bool_t reduce_memory;

    /** Tokenizer configuration for downloading missing tokenizer files
     *  Apple's compiled CoreML models don't include tokenizer files */
    rac_diffusion_tokenizer_config_t tokenizer;
} rac_diffusion_config_t;

/**
 * @brief Default diffusion configuration
 */
static const rac_diffusion_config_t RAC_DIFFUSION_CONFIG_DEFAULT = {
    .model_id = RAC_NULL,
    .preferred_framework = 99, // RAC_FRAMEWORK_UNKNOWN
    .model_variant = RAC_DIFFUSION_MODEL_SD_1_5,
    .enable_safety_checker = RAC_TRUE,
    .reduce_memory = RAC_FALSE,
    .tokenizer = {.source = RAC_DIFFUSION_TOKENIZER_SD_1_5,
                  .custom_base_url = RAC_NULL,
                  .auto_download = RAC_TRUE}};

// =============================================================================
// OPTIONS - Generation options
// =============================================================================

/**
 * @brief Diffusion generation options
 *
 * Options for controlling image generation.
 */
typedef struct rac_diffusion_options {
    /** Text prompt describing the desired image */
    const char* prompt;

    /** Negative prompt - things to avoid in the image (can be NULL) */
    const char* negative_prompt;

    /** Output image width in pixels (default: 512 for SD 1.5, 1024 for SDXL) */
    int32_t width;

    /** Output image height in pixels (default: 512 for SD 1.5, 1024 for SDXL) */
    int32_t height;

    /** Number of denoising steps (default: 28, range: 10-50) */
    int32_t steps;

    /** Classifier-free guidance scale (default: 7.5, range: 1.0-20.0) */
    float guidance_scale;

    /** Random seed for reproducibility (-1 for random, default: -1) */
    int64_t seed;

    /** Scheduler/sampler algorithm (default: DPM++ 2M Karras) */
    rac_diffusion_scheduler_t scheduler;

    // --- Image-to-image / Inpainting options ---

    /** Generation mode (text-to-image, img2img, inpainting) */
    rac_diffusion_mode_t mode;

    /** Input image RGBA data for img2img/inpainting (can be NULL) */
    const uint8_t* input_image_data;

    /** Input image data size in bytes */
    size_t input_image_size;

    /** Input image width (required if input_image_data is set) */
    int32_t input_image_width;

    /** Input image height (required if input_image_data is set) */
    int32_t input_image_height;

    /** Mask image data for inpainting - grayscale (can be NULL) */
    const uint8_t* mask_data;

    /** Mask data size in bytes */
    size_t mask_size;

    /** Denoising strength for img2img (0.0-1.0, default: 0.75) */
    float denoise_strength;

    // --- Progress reporting options ---

    /** Report intermediate images during generation (default: false) */
    rac_bool_t report_intermediate_images;

    /** Report progress every N steps (default: 1) */
    int32_t progress_stride;
} rac_diffusion_options_t;

/**
 * @brief Default diffusion generation options
 */
static const rac_diffusion_options_t RAC_DIFFUSION_OPTIONS_DEFAULT = {
    .prompt = RAC_NULL,
    .negative_prompt = RAC_NULL,
    .width = 512,
    .height = 512,
    .steps = 28,
    .guidance_scale = 7.5f,
    .seed = -1,
    .scheduler = RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS,
    .mode = RAC_DIFFUSION_MODE_TEXT_TO_IMAGE,
    .input_image_data = RAC_NULL,
    .input_image_size = 0,
    .input_image_width = 0,
    .input_image_height = 0,
    .mask_data = RAC_NULL,
    .mask_size = 0,
    .denoise_strength = 0.75f,
    .report_intermediate_images = RAC_FALSE,
    .progress_stride = 1};

// =============================================================================
// PROGRESS - Generation progress
// =============================================================================

/**
 * @brief Diffusion generation progress
 *
 * Reports progress during image generation.
 */
typedef struct rac_diffusion_progress {
    /** Progress percentage (0.0 - 1.0) */
    float progress;

    /** Current step number (1-based) */
    int32_t current_step;

    /** Total number of steps */
    int32_t total_steps;

    /** Current stage description (e.g., "Encoding", "Denoising", "Decoding") */
    const char* stage;

    /** Intermediate image RGBA data (can be NULL if not requested) */
    const uint8_t* intermediate_image_data;

    /** Intermediate image data size */
    size_t intermediate_image_size;

    /** Intermediate image width */
    int32_t intermediate_image_width;

    /** Intermediate image height */
    int32_t intermediate_image_height;
} rac_diffusion_progress_t;

// =============================================================================
// RESULT - Generation result
// =============================================================================

/**
 * @brief Diffusion generation result
 *
 * Contains the generated image and metadata.
 */
typedef struct rac_diffusion_result {
    /** Generated image RGBA data (owned, must be freed with rac_diffusion_result_free) */
    uint8_t* image_data;

    /** Image data size in bytes */
    size_t image_size;

    /** Image width in pixels */
    int32_t width;

    /** Image height in pixels */
    int32_t height;

    /** Seed used for generation (useful for reproducibility) */
    int64_t seed_used;

    /** Total generation time in milliseconds */
    int64_t generation_time_ms;

    /** Whether the image was flagged by safety checker */
    rac_bool_t safety_flagged;

    /** Error code if generation failed (RAC_SUCCESS on success) */
    rac_result_t error_code;

    /** Error message if generation failed (can be NULL) */
    char* error_message;
} rac_diffusion_result_t;

// =============================================================================
// INFO - Service information
// =============================================================================

/**
 * @brief Diffusion service information
 *
 * Information about the loaded diffusion service.
 */
typedef struct rac_diffusion_info {
    /** Whether the service is ready for generation */
    rac_bool_t is_ready;

    /** Current model identifier (can be NULL) */
    const char* current_model;

    /** Model variant */
    rac_diffusion_model_variant_t model_variant;

    /** Whether text-to-image is supported */
    rac_bool_t supports_text_to_image;

    /** Whether image-to-image is supported */
    rac_bool_t supports_image_to_image;

    /** Whether inpainting is supported */
    rac_bool_t supports_inpainting;

    /** Whether safety checker is enabled */
    rac_bool_t safety_checker_enabled;

    /** Maximum supported width */
    int32_t max_width;

    /** Maximum supported height */
    int32_t max_height;
} rac_diffusion_info_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief Diffusion progress callback
 *
 * Called during generation to report progress.
 *
 * @param progress Progress information
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to cancel generation
 */
typedef rac_bool_t (*rac_diffusion_progress_callback_fn)(const rac_diffusion_progress_t* progress,
                                                         void* user_data);

/**
 * @brief Diffusion completion callback
 *
 * Called when generation completes successfully.
 *
 * @param result Generation result
 * @param user_data User-provided context
 */
typedef void (*rac_diffusion_complete_callback_fn)(const rac_diffusion_result_t* result,
                                                   void* user_data);

/**
 * @brief Diffusion error callback
 *
 * Called when generation fails.
 *
 * @param error_code Error code
 * @param error_message Error message
 * @param user_data User-provided context
 */
typedef void (*rac_diffusion_error_callback_fn)(rac_result_t error_code, const char* error_message,
                                                void* user_data);

// =============================================================================
// CAPABILITY FLAGS
// =============================================================================

/** Supports text-to-image generation */
#define RAC_DIFFUSION_CAP_TEXT_TO_IMAGE (1 << 0)

/** Supports image-to-image transformation */
#define RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE (1 << 1)

/** Supports inpainting with mask */
#define RAC_DIFFUSION_CAP_INPAINTING (1 << 2)

/** Supports intermediate image reporting */
#define RAC_DIFFUSION_CAP_INTERMEDIATE_IMAGES (1 << 3)

/** Has safety checker */
#define RAC_DIFFUSION_CAP_SAFETY_CHECKER (1 << 4)

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free diffusion result resources
 *
 * @param result Result to free (can be NULL)
 */
RAC_API void rac_diffusion_result_free(rac_diffusion_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_TYPES_H */
