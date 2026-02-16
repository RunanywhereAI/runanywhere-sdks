/**
 * @file rac_image_utils.cpp
 * @brief RunAnywhere Commons - Image Utilities Implementation
 *
 * Image loading and processing utilities for VLM backends.
 * Uses stb_image for decoding various image formats.
 */

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION

#include "rac/utils/rac_image_utils.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

// stb_image single-header library for image loading
// Will be included via CMake or directly
#ifdef RAC_USE_STB_IMAGE
#include "stb_image.h"
#include "stb_image_resize2.h"
#else
// Minimal fallback if stb_image is not available
// This will return an error when trying to load images
#endif

static const char* LOG_CAT = "ImageUtils";

// =============================================================================
// BASE64 DECODING
// =============================================================================

namespace {

/**
 * Base64 decoding table
 */
static const int base64_decode_table[256] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62,
    -1, -1, -1, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, -1, 0,
    1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24, 25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
};

/**
 * Decode base64 string to bytes
 */
std::vector<uint8_t> base64_decode(const char* data, size_t len) {
    std::vector<uint8_t> result;
    if (!data || len == 0)
        return result;

    // Strip data URI prefix if present (e.g., "data:image/png;base64,")
    std::string input(data, len);
    size_t comma_pos = input.find(',');
    if (comma_pos != std::string::npos) {
        input = input.substr(comma_pos + 1);
    }

    // Remove whitespace
    input.erase(std::remove_if(input.begin(), input.end(), ::isspace), input.end());

    size_t input_len = input.length();
    if (input_len == 0)
        return result;

    // Calculate output size
    size_t out_len = (input_len / 4) * 3;
    if (input_len >= 2 && input[input_len - 1] == '=')
        out_len--;
    if (input_len >= 2 && input[input_len - 2] == '=')
        out_len--;

    result.resize(out_len);

    size_t out_idx = 0;
    for (size_t i = 0; i < input_len;) {
        int v1 = (i < input_len) ? base64_decode_table[(uint8_t)input[i++]] : 0;
        int v2 = (i < input_len) ? base64_decode_table[(uint8_t)input[i++]] : 0;
        int v3 = (i < input_len) ? base64_decode_table[(uint8_t)input[i++]] : 0;
        int v4 = (i < input_len) ? base64_decode_table[(uint8_t)input[i++]] : 0;

        if (v1 < 0 || v2 < 0)
            break;

        if (out_idx < out_len) {
            result[out_idx++] = (v1 << 2) | (v2 >> 4);
        }
        if (v3 >= 0 && out_idx < out_len) {
            result[out_idx++] = ((v2 & 0x0F) << 4) | (v3 >> 2);
        }
        if (v4 >= 0 && out_idx < out_len) {
            result[out_idx++] = ((v3 & 0x03) << 6) | v4;
        }
    }

    result.resize(out_idx);
    return result;
}

/**
 * Simple bilinear resize without stb
 */
void bilinear_resize(const uint8_t* src, int src_w, int src_h, uint8_t* dst, int dst_w, int dst_h,
                     int channels) {
    float x_ratio = static_cast<float>(src_w - 1) / static_cast<float>(dst_w - 1);
    float y_ratio = static_cast<float>(src_h - 1) / static_cast<float>(dst_h - 1);

    for (int y = 0; y < dst_h; y++) {
        for (int x = 0; x < dst_w; x++) {
            float src_x = x * x_ratio;
            float src_y = y * y_ratio;

            int x0 = static_cast<int>(src_x);
            int y0 = static_cast<int>(src_y);
            int x1 = std::min(x0 + 1, src_w - 1);
            int y1 = std::min(y0 + 1, src_h - 1);

            float x_lerp = src_x - x0;
            float y_lerp = src_y - y0;

            for (int c = 0; c < channels; c++) {
                float v00 = src[(y0 * src_w + x0) * channels + c];
                float v01 = src[(y0 * src_w + x1) * channels + c];
                float v10 = src[(y1 * src_w + x0) * channels + c];
                float v11 = src[(y1 * src_w + x1) * channels + c];

                float v0 = v00 * (1 - x_lerp) + v01 * x_lerp;
                float v1 = v10 * (1 - x_lerp) + v11 * x_lerp;
                float v = v0 * (1 - y_lerp) + v1 * y_lerp;

                dst[(y * dst_w + x) * channels + c] = static_cast<uint8_t>(v + 0.5f);
            }
        }
    }
}

}  // namespace

// =============================================================================
// IMAGE LOADING
// =============================================================================

extern "C" {

rac_result_t rac_image_load_file(const char* file_path, rac_image_data_t* out_image) {
    if (!file_path || !out_image) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_image, 0, sizeof(rac_image_data_t));

#ifdef RAC_USE_STB_IMAGE
    int width, height, channels;
    uint8_t* data = stbi_load(file_path, &width, &height, &channels, 3);  // Force RGB

    if (!data) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load image: %s - %s", file_path, stbi_failure_reason());
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    out_image->pixels = data;
    out_image->width = width;
    out_image->height = height;
    out_image->channels = 3;
    out_image->size = static_cast<size_t>(width) * height * 3;

    RAC_LOG_DEBUG(LOG_CAT, "Loaded image: %s (%dx%d)", file_path, width, height);
    return RAC_SUCCESS;
#else
    RAC_LOG_ERROR(LOG_CAT, "stb_image not available - cannot load images");
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

rac_result_t rac_image_decode_base64(const char* base64_data, size_t data_size,
                                     rac_image_data_t* out_image) {
    if (!base64_data || !out_image) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_image, 0, sizeof(rac_image_data_t));

    // Decode base64
    std::vector<uint8_t> decoded = base64_decode(base64_data, data_size);
    if (decoded.empty()) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to decode base64 data");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Decode image from bytes
    return rac_image_decode_bytes(decoded.data(), decoded.size(), out_image);
}

rac_result_t rac_image_decode_bytes(const uint8_t* data, size_t data_size,
                                    rac_image_data_t* out_image) {
    if (!data || !out_image) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_image, 0, sizeof(rac_image_data_t));

#ifdef RAC_USE_STB_IMAGE
    int width, height, channels;
    uint8_t* pixels =
        stbi_load_from_memory(data, static_cast<int>(data_size), &width, &height, &channels, 3);

    if (!pixels) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to decode image from bytes: %s", stbi_failure_reason());
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    out_image->pixels = pixels;
    out_image->width = width;
    out_image->height = height;
    out_image->channels = 3;
    out_image->size = static_cast<size_t>(width) * height * 3;

    RAC_LOG_DEBUG(LOG_CAT, "Decoded image from bytes (%dx%d)", width, height);
    return RAC_SUCCESS;
#else
    RAC_LOG_ERROR(LOG_CAT, "stb_image not available - cannot decode images");
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

// =============================================================================
// IMAGE PROCESSING
// =============================================================================

rac_result_t rac_image_resize(const rac_image_data_t* image, int32_t new_width, int32_t new_height,
                              rac_image_data_t* out_image) {
    if (!image || !image->pixels || !out_image) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (new_width <= 0 || new_height <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    memset(out_image, 0, sizeof(rac_image_data_t));

    size_t out_size = static_cast<size_t>(new_width) * new_height * image->channels;
    auto* out_pixels = static_cast<uint8_t*>(malloc(out_size));
    if (!out_pixels) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

#ifdef RAC_USE_STB_IMAGE
    stbir_resize_uint8_srgb(image->pixels, image->width, image->height, 0, out_pixels, new_width,
                            new_height, 0, static_cast<stbir_pixel_layout>(image->channels));
#else
    bilinear_resize(image->pixels, image->width, image->height, out_pixels, new_width, new_height,
                    image->channels);
#endif

    out_image->pixels = out_pixels;
    out_image->width = new_width;
    out_image->height = new_height;
    out_image->channels = image->channels;
    out_image->size = out_size;

    RAC_LOG_DEBUG(LOG_CAT, "Resized image from %dx%d to %dx%d", image->width, image->height,
                  new_width, new_height);
    return RAC_SUCCESS;
}

rac_result_t rac_image_resize_max(const rac_image_data_t* image, int32_t max_size,
                                  rac_image_data_t* out_image) {
    if (!image || !image->pixels || !out_image) {
        return RAC_ERROR_NULL_POINTER;
    }

    int32_t new_width, new_height;
    rac_image_calc_resize(image->width, image->height, max_size, &new_width, &new_height);

    // If already smaller than max_size, just copy
    if (new_width == image->width && new_height == image->height) {
        size_t size = image->size;
        auto* pixels = static_cast<uint8_t*>(malloc(size));
        if (!pixels) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(pixels, image->pixels, size);

        out_image->pixels = pixels;
        out_image->width = image->width;
        out_image->height = image->height;
        out_image->channels = image->channels;
        out_image->size = size;
        return RAC_SUCCESS;
    }

    return rac_image_resize(image, new_width, new_height, out_image);
}

rac_result_t rac_image_normalize(const rac_image_data_t* image, const float* mean, const float* std,
                                 rac_image_float_t* out_float) {
    if (!image || !image->pixels || !out_float) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_float, 0, sizeof(rac_image_float_t));

    // Default mean and std (ImageNet-style normalization)
    float default_mean[3] = {0.0f, 0.0f, 0.0f};
    float default_std[3] = {1.0f, 1.0f, 1.0f};

    const float* m = mean ? mean : default_mean;
    const float* s = std ? std : default_std;

    size_t count = static_cast<size_t>(image->width) * image->height * image->channels;
    auto* pixels = static_cast<float*>(malloc(count * sizeof(float)));
    if (!pixels) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Normalize: (pixel / 255.0 - mean) / std
    for (size_t i = 0; i < count; i++) {
        int channel = i % image->channels;
        float val = static_cast<float>(image->pixels[i]) / 255.0f;
        pixels[i] = (val - m[channel]) / s[channel];
    }

    out_float->pixels = pixels;
    out_float->width = image->width;
    out_float->height = image->height;
    out_float->channels = image->channels;
    out_float->count = count;

    return RAC_SUCCESS;
}

rac_result_t rac_image_to_chw(const rac_image_float_t* image, rac_image_float_t* out_chw) {
    if (!image || !image->pixels || !out_chw) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_chw, 0, sizeof(rac_image_float_t));

    size_t count = image->count;
    auto* pixels = static_cast<float*>(malloc(count * sizeof(float)));
    if (!pixels) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    int w = image->width;
    int h = image->height;
    int c = image->channels;

    // Convert HWC to CHW
    for (int ch = 0; ch < c; ch++) {
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int hwc_idx = (y * w + x) * c + ch;
                int chw_idx = ch * h * w + y * w + x;
                pixels[chw_idx] = image->pixels[hwc_idx];
            }
        }
    }

    out_chw->pixels = pixels;
    out_chw->width = image->width;
    out_chw->height = image->height;
    out_chw->channels = image->channels;
    out_chw->count = count;

    return RAC_SUCCESS;
}

// =============================================================================
// PIXEL FORMAT CONVERSION
// =============================================================================

rac_result_t rac_image_convert_rgba_to_rgb(const uint8_t* rgba_data, uint32_t width,
                                           uint32_t height, uint32_t row_stride,
                                           uint8_t* out_rgb_data, size_t out_size) {
    if (!rgba_data || !out_rgb_data)
        return RAC_ERROR_INVALID_ARGUMENT;

    size_t required = (size_t)width * height * 3;
    if (out_size < required)
        return RAC_ERROR_INVALID_ARGUMENT;

    uint32_t effective_stride = (row_stride > 0) ? row_stride : width * 4;
    size_t out_idx = 0;

    for (uint32_t y = 0; y < height; y++) {
        const uint8_t* row = rgba_data + y * effective_stride;
        for (uint32_t x = 0; x < width; x++) {
            uint32_t src = x * 4;
            out_rgb_data[out_idx++] = row[src];     // R
            out_rgb_data[out_idx++] = row[src + 1]; // G
            out_rgb_data[out_idx++] = row[src + 2]; // B
            // Skip alpha at row[src + 3]
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_image_convert_bgra_to_rgb(const uint8_t* bgra_data, uint32_t width,
                                           uint32_t height, uint32_t bytes_per_row,
                                           uint8_t* out_rgb_data, size_t out_size) {
    if (!bgra_data || !out_rgb_data)
        return RAC_ERROR_INVALID_ARGUMENT;

    size_t required = (size_t)width * height * 3;
    if (out_size < required)
        return RAC_ERROR_INVALID_ARGUMENT;

    uint32_t effective_stride = (bytes_per_row > 0) ? bytes_per_row : width * 4;
    size_t out_idx = 0;

    for (uint32_t y = 0; y < height; y++) {
        const uint8_t* row = bgra_data + y * effective_stride;
        for (uint32_t x = 0; x < width; x++) {
            uint32_t src = x * 4;
            out_rgb_data[out_idx++] = row[src + 2]; // R (from BGRA offset +2)
            out_rgb_data[out_idx++] = row[src + 1]; // G (from BGRA offset +1)
            out_rgb_data[out_idx++] = row[src];     // B (from BGRA offset +0)
            // Skip alpha at row[src + 3]
        }
    }

    return RAC_SUCCESS;
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

void rac_image_free(rac_image_data_t* image) {
    if (!image)
        return;

    if (image->pixels) {
#ifdef RAC_USE_STB_IMAGE
        stbi_image_free(image->pixels);
#else
        free(image->pixels);
#endif
        image->pixels = nullptr;
    }

    image->width = 0;
    image->height = 0;
    image->channels = 0;
    image->size = 0;
}

void rac_image_float_free(rac_image_float_t* image) {
    if (!image)
        return;

    if (image->pixels) {
        free(image->pixels);
        image->pixels = nullptr;
    }

    image->width = 0;
    image->height = 0;
    image->channels = 0;
    image->count = 0;
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

void rac_image_calc_resize(int32_t width, int32_t height, int32_t max_size, int32_t* out_width,
                           int32_t* out_height) {
    if (!out_width || !out_height)
        return;

    if (width <= max_size && height <= max_size) {
        *out_width = width;
        *out_height = height;
        return;
    }

    float aspect = static_cast<float>(width) / static_cast<float>(height);

    if (width > height) {
        *out_width = max_size;
        *out_height = static_cast<int32_t>(max_size / aspect + 0.5f);
    } else {
        *out_height = max_size;
        *out_width = static_cast<int32_t>(max_size * aspect + 0.5f);
    }

    // Ensure minimum dimensions
    if (*out_width < 1)
        *out_width = 1;
    if (*out_height < 1)
        *out_height = 1;
}

}  // extern "C"
