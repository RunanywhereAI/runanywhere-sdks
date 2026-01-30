/**
 * @file rac_image_utils.h
 * @brief RunAnywhere Commons - Image Utilities
 *
 * Image loading and processing utilities for VLM backends.
 * Supports loading from file paths, decoding base64, and resizing.
 */

#ifndef RAC_IMAGE_UTILS_H
#define RAC_IMAGE_UTILS_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// IMAGE DATA STRUCTURES
// =============================================================================

/**
 * @brief Loaded image data
 *
 * Contains RGB pixel data after loading an image.
 * Must be freed with rac_image_free().
 */
typedef struct rac_image_data {
    /** Raw RGB pixel data (RGBRGBRGB...) */
    uint8_t* pixels;

    /** Image width in pixels */
    int32_t width;

    /** Image height in pixels */
    int32_t height;

    /** Number of channels (3 for RGB) */
    int32_t channels;

    /** Total size in bytes (width * height * channels) */
    size_t size;
} rac_image_data_t;

/**
 * @brief Normalized float image data
 *
 * Contains normalized float32 pixel data (values in [-1, 1] or [0, 1]).
 * Used by vision encoders.
 */
typedef struct rac_image_float {
    /** Normalized float pixel data */
    float* pixels;

    /** Image width in pixels */
    int32_t width;

    /** Image height in pixels */
    int32_t height;

    /** Number of channels (3 for RGB) */
    int32_t channels;

    /** Total number of floats (width * height * channels) */
    size_t count;
} rac_image_float_t;

// =============================================================================
// IMAGE LOADING
// =============================================================================

/**
 * @brief Load an image from a file path
 *
 * Supports JPEG, PNG, BMP, GIF, and other common formats via stb_image.
 * Output is always RGB (3 channels).
 *
 * @param file_path Path to the image file
 * @param out_image Output: Loaded image data (must be freed with rac_image_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_load_file(const char* file_path, rac_image_data_t* out_image);

/**
 * @brief Decode a base64-encoded image
 *
 * Decodes base64 data and loads the image.
 * Supports the same formats as rac_image_load_file.
 *
 * @param base64_data Base64-encoded image data
 * @param data_size Length of the base64 string
 * @param out_image Output: Loaded image data (must be freed with rac_image_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_decode_base64(const char* base64_data, size_t data_size,
                                             rac_image_data_t* out_image);

/**
 * @brief Decode image from raw bytes
 *
 * Decodes an image from raw bytes (e.g., from network response).
 *
 * @param data Raw image data (JPEG, PNG, etc.)
 * @param data_size Size of the data in bytes
 * @param out_image Output: Loaded image data (must be freed with rac_image_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_decode_bytes(const uint8_t* data, size_t data_size,
                                            rac_image_data_t* out_image);

// =============================================================================
// IMAGE PROCESSING
// =============================================================================

/**
 * @brief Resize an image
 *
 * Resizes the image to the specified dimensions using bilinear interpolation.
 *
 * @param image Input image
 * @param new_width Target width
 * @param new_height Target height
 * @param out_image Output: Resized image (must be freed with rac_image_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_resize(const rac_image_data_t* image, int32_t new_width,
                                      int32_t new_height, rac_image_data_t* out_image);

/**
 * @brief Resize an image maintaining aspect ratio
 *
 * Resizes the image so that the longest dimension equals max_size.
 * Aspect ratio is preserved.
 *
 * @param image Input image
 * @param max_size Maximum dimension (width or height)
 * @param out_image Output: Resized image (must be freed with rac_image_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_resize_max(const rac_image_data_t* image, int32_t max_size,
                                          rac_image_data_t* out_image);

/**
 * @brief Normalize image to float values
 *
 * Converts uint8 pixels to float32 with optional mean/std normalization.
 * Commonly used for vision encoders (CLIP, SigLIP, etc.).
 *
 * Formula: pixel_normalized = (pixel / 255.0 - mean) / std
 *
 * @param image Input image
 * @param mean Per-channel mean values (array of 3 floats, or NULL for [0,0,0])
 * @param std Per-channel std values (array of 3 floats, or NULL for [1,1,1])
 * @param out_float Output: Normalized float image (must be freed with rac_image_float_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_normalize(const rac_image_data_t* image, const float* mean,
                                         const float* std, rac_image_float_t* out_float);

/**
 * @brief Convert RGB to CHW format
 *
 * Converts from HWC (Height, Width, Channels) to CHW format.
 * Many neural networks expect CHW format.
 *
 * @param image Input float image in HWC format
 * @param out_chw Output: Float image in CHW format (must be freed with rac_image_float_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_image_to_chw(const rac_image_float_t* image, rac_image_float_t* out_chw);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free image data
 *
 * Frees the pixel data allocated by image loading functions.
 *
 * @param image Image to free (can be NULL)
 */
RAC_API void rac_image_free(rac_image_data_t* image);

/**
 * @brief Free float image data
 *
 * Frees the pixel data allocated by normalization functions.
 *
 * @param image Float image to free (can be NULL)
 */
RAC_API void rac_image_float_free(rac_image_float_t* image);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * @brief Calculate resized dimensions maintaining aspect ratio
 *
 * @param width Original width
 * @param height Original height
 * @param max_size Maximum dimension
 * @param out_width Output: New width
 * @param out_height Output: New height
 */
RAC_API void rac_image_calc_resize(int32_t width, int32_t height, int32_t max_size,
                                   int32_t* out_width, int32_t* out_height);

#ifdef __cplusplus
}
#endif

#endif /* RAC_IMAGE_UTILS_H */
