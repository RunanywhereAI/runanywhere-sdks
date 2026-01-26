/**
 * @file rac_vlm_types.h
 * @brief RunAnywhere Commons - VLM Types and Data Structures
 *
 * Defines data structures for Vision Language Model (VLM) operations.
 * Supports image input (file path, RGB pixels, base64), generation options,
 * results, and streaming callbacks.
 *
 * For the service interface, see rac_vlm_service.h.
 */

#ifndef RAC_VLM_TYPES_H
#define RAC_VLM_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// IMAGE INPUT - Supports multiple input formats
// =============================================================================

/**
 * @brief VLM image input format enumeration
 */
typedef enum rac_vlm_image_format {
    RAC_VLM_IMAGE_FORMAT_FILE_PATH = 0,   /**< Path to image file (JPEG, PNG, etc.) */
    RAC_VLM_IMAGE_FORMAT_RGB_PIXELS = 1,  /**< Raw RGB pixel buffer (RGBRGBRGB...) */
    RAC_VLM_IMAGE_FORMAT_BASE64 = 2,      /**< Base64-encoded image data */
} rac_vlm_image_format_t;

/**
 * @brief VLM image input structure
 *
 * Represents an image input for VLM processing. Supports three formats:
 * - FILE_PATH: Path to an image file on disk
 * - RGB_PIXELS: Raw RGB pixel data with width/height
 * - BASE64: Base64-encoded image data
 */
typedef struct rac_vlm_image {
    /** Image format type */
    rac_vlm_image_format_t format;

    /** Path to image file (for FILE_PATH format) */
    const char* file_path;

    /** Raw RGB pixel data (for RGB_PIXELS format, layout: RGBRGBRGB...) */
    const uint8_t* pixel_data;

    /** Base64-encoded image data (for BASE64 format) */
    const char* base64_data;

    /** Image width in pixels (required for RGB_PIXELS, 0 otherwise) */
    uint32_t width;

    /** Image height in pixels (required for RGB_PIXELS, 0 otherwise) */
    uint32_t height;

    /** Size of pixel_data or base64_data in bytes */
    size_t data_size;
} rac_vlm_image_t;

// =============================================================================
// OPTIONS - VLM Generation Options
// =============================================================================

/**
 * @brief VLM generation options
 *
 * Controls text generation behavior for VLM inference.
 * Combines standard LLM options with VLM-specific parameters.
 */
typedef struct rac_vlm_options {
    // ── Standard Generation Parameters ──
    /** Maximum number of tokens to generate (default: 2048) */
    int32_t max_tokens;

    /** Temperature for sampling (0.0 - 2.0, default: 0.7) */
    float temperature;

    /** Top-p sampling parameter (default: 0.9) */
    float top_p;

    /** Stop sequences (null-terminated array, can be NULL) */
    const char* const* stop_sequences;

    /** Number of stop sequences */
    size_t num_stop_sequences;

    /** Enable streaming mode (default: true) */
    rac_bool_t streaming_enabled;

    /** System prompt (can be NULL) */
    const char* system_prompt;

    // ── VLM-Specific Parameters ──
    /** Max image dimension for resize (0 = model default) */
    int32_t max_image_size;

    /** Number of CPU threads for vision encoder (0 = auto) */
    int32_t n_threads;

    /** Use GPU for vision encoding */
    rac_bool_t use_gpu;
} rac_vlm_options_t;

/**
 * @brief Default VLM generation options
 */
#define RAC_VLM_OPTIONS_DEFAULT                                                                    \
    {                                                                                              \
        .max_tokens = 2048, .temperature = 0.7f, .top_p = 0.9f, .stop_sequences = RAC_NULL,        \
        .num_stop_sequences = 0, .streaming_enabled = RAC_TRUE, .system_prompt = RAC_NULL,         \
        .max_image_size = 0, .n_threads = 0, .use_gpu = RAC_TRUE                                   \
    }

// =============================================================================
// CONFIGURATION - VLM Component Configuration
// =============================================================================

/**
 * @brief VLM component configuration
 *
 * Configuration for initializing a VLM component.
 */
typedef struct rac_vlm_config {
    /** Model ID (optional - uses default if NULL) */
    const char* model_id;

    /** Preferred framework for generation (use RAC_FRAMEWORK_UNKNOWN for auto) */
    int32_t preferred_framework;

    /** Context length - max tokens the model can handle (default: 4096) */
    int32_t context_length;

    /** Temperature for sampling (0.0 - 2.0, default: 0.7) */
    float temperature;

    /** Maximum tokens to generate (default: 2048) */
    int32_t max_tokens;

    /** System prompt for generation (can be NULL) */
    const char* system_prompt;

    /** Enable streaming mode (default: true) */
    rac_bool_t streaming_enabled;
} rac_vlm_config_t;

/**
 * @brief Default VLM configuration
 */
static const rac_vlm_config_t RAC_VLM_CONFIG_DEFAULT = {.model_id = RAC_NULL,
                                                        .preferred_framework =
                                                            99,  // RAC_FRAMEWORK_UNKNOWN
                                                        .context_length = 4096,
                                                        .temperature = 0.7f,
                                                        .max_tokens = 2048,
                                                        .system_prompt = RAC_NULL,
                                                        .streaming_enabled = RAC_TRUE};

// =============================================================================
// RESULTS - VLM Generation Results
// =============================================================================

/**
 * @brief VLM generation result
 *
 * Contains the generated text and detailed metrics for VLM inference.
 */
typedef struct rac_vlm_result {
    /** Generated text (owned, must be freed with rac_vlm_result_free) */
    char* text;

    /** Number of tokens in prompt (including text tokens) */
    int32_t prompt_tokens;

    /** Number of vision/image tokens specifically */
    int32_t image_tokens;

    /** Number of tokens generated */
    int32_t completion_tokens;

    /** Total tokens (prompt + completion) */
    int32_t total_tokens;

    /** Time to first token in milliseconds */
    int64_t time_to_first_token_ms;

    /** Time spent encoding the image in milliseconds */
    int64_t image_encode_time_ms;

    /** Total generation time in milliseconds */
    int64_t total_time_ms;

    /** Tokens generated per second */
    float tokens_per_second;
} rac_vlm_result_t;

// =============================================================================
// SERVICE INFO - VLM Service Information
// =============================================================================

/**
 * @brief VLM service handle info
 *
 * Provides information about a VLM service instance.
 */
typedef struct rac_vlm_info {
    /** Whether the service is ready for generation */
    rac_bool_t is_ready;

    /** Current model identifier (can be NULL if not loaded) */
    const char* current_model;

    /** Context length (0 if unknown) */
    int32_t context_length;

    /** Whether streaming is supported */
    rac_bool_t supports_streaming;

    /** Whether multiple images per request are supported */
    rac_bool_t supports_multiple_images;

    /** Vision encoder type ("clip", "siglip", "fastvithd", etc.) */
    const char* vision_encoder_type;
} rac_vlm_info_t;

// =============================================================================
// CALLBACKS - Streaming Callbacks
// =============================================================================

/**
 * @brief Simple VLM streaming callback
 *
 * Called for each generated token during streaming.
 *
 * @param token The generated token string
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop generation
 */
typedef rac_bool_t (*rac_vlm_stream_callback_fn)(const char* token, void* user_data);

/**
 * @brief Extended token event structure
 *
 * Provides detailed information about each token during streaming.
 */
typedef struct rac_vlm_token_event {
    /** The generated token text */
    const char* token;

    /** Token index in the sequence */
    int32_t token_index;

    /** Is this the final token? */
    rac_bool_t is_final;

    /** Tokens generated per second so far */
    float tokens_per_second;
} rac_vlm_token_event_t;

/**
 * @brief Extended streaming callback with token event details
 *
 * @param event Token event details
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop generation
 */
typedef rac_bool_t (*rac_vlm_token_event_callback_fn)(const rac_vlm_token_event_t* event,
                                                      void* user_data);

// =============================================================================
// COMPONENT CALLBACKS - For component-level streaming
// =============================================================================

/**
 * @brief VLM component token callback
 *
 * @param token The generated token
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop
 */
typedef rac_bool_t (*rac_vlm_component_token_callback_fn)(const char* token, void* user_data);

/**
 * @brief VLM component completion callback
 *
 * Called when streaming is complete with final result.
 *
 * @param result Final generation result with metrics
 * @param user_data User-provided context
 */
typedef void (*rac_vlm_component_complete_callback_fn)(const rac_vlm_result_t* result,
                                                       void* user_data);

/**
 * @brief VLM component error callback
 *
 * Called if streaming fails.
 *
 * @param error_code Error code
 * @param error_message Error message
 * @param user_data User-provided context
 */
typedef void (*rac_vlm_component_error_callback_fn)(rac_result_t error_code,
                                                    const char* error_message, void* user_data);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free VLM result resources
 *
 * Frees the text and any other owned resources in the result.
 *
 * @param result Result to free (can be NULL)
 */
RAC_API void rac_vlm_result_free(rac_vlm_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_TYPES_H */
