// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — image utility C ABI.
//
// Pixel-buffer manipulation helpers used by the VLM dispatch layer
// (resize, normalize, format conversion, base64 decode, ...). Mirrors
// the legacy `rac_image_utils.h` capability surface.
//
// Pure-C implementation (no external image-decoder dependency). PNG/JPEG
// decoding is delegated to the platform via the platform adapter (iOS
// CGImage / Android BitmapFactory / Web ImageBitmap) so we don't drag
// libpng/libjpeg into the core for mobile.

#ifndef RA_IMAGE_H
#define RA_IMAGE_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"
#include "ra_vlm.h"

#ifdef __cplusplus
extern "C" {
#endif

// 8-bit-per-channel image buffer.
typedef struct {
    uint8_t*               data;       // Heap-allocated; free with ra_image_free
    int32_t                width;
    int32_t                height;
    int32_t                row_stride; // bytes per row
    ra_vlm_image_format_t  format;
} ra_image_data_t;

// 32-bit-per-channel float image buffer (CHW or HWC).
typedef struct {
    float*  data;     // Heap-allocated; free with ra_image_float_free
    int32_t width;
    int32_t height;
    int32_t channels;
    uint8_t channels_first;  // 0 = HWC, non-zero = CHW
    uint8_t _reserved0[3];
} ra_image_float_t;

// ---------------------------------------------------------------------------
// Loading / decoding
// ---------------------------------------------------------------------------

// Load a PNG/JPEG file from disk via the platform adapter (calls
// adapter->file_read + decodes on the platform side). Returns RA_OK and
// populates `out_image` on success.
ra_status_t ra_image_load_file(const char* path, ra_image_data_t* out_image);

// Decode raw bytes (PNG/JPEG/BMP) using the platform adapter.
ra_status_t ra_image_decode_bytes(const uint8_t*   bytes,
                                   int32_t          size,
                                   ra_image_data_t* out_image);

// Decode a base64-encoded image string.
ra_status_t ra_image_decode_base64(const char*      base64_text,
                                    ra_image_data_t* out_image);

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

// Compute new dimensions to fit within `max_dim` while preserving aspect
// ratio. `out_w` / `out_h` are the result.
void ra_image_calc_resize(int32_t in_w, int32_t in_h, int32_t max_dim,
                          int32_t* out_w, int32_t* out_h);

// Resize using nearest-neighbour or bilinear (sampler=0 for NN, 1 for bilinear).
ra_status_t ra_image_resize(const ra_image_data_t* in_image,
                             int32_t                 new_w,
                             int32_t                 new_h,
                             int32_t                 sampler,
                             ra_image_data_t*        out_image);

// Resize so that the longest side is ≤ max_dim, preserving aspect ratio.
ra_status_t ra_image_resize_max(const ra_image_data_t* in_image,
                                 int32_t                 max_dim,
                                 int32_t                 sampler,
                                 ra_image_data_t*        out_image);

// ---------------------------------------------------------------------------
// Format conversion
// ---------------------------------------------------------------------------
ra_status_t ra_image_convert_rgba_to_rgb(const ra_image_data_t* in_image,
                                          ra_image_data_t*       out_image);
ra_status_t ra_image_convert_bgra_to_rgb(const ra_image_data_t* in_image,
                                          ra_image_data_t*       out_image);

// Convert HWC uint8 to CHW float, normalising with `mean` and `std`
// (one float per channel).
ra_status_t ra_image_to_chw(const ra_image_data_t* in_image,
                             const float*           mean,
                             const float*           std,
                             int32_t                num_channels,
                             ra_image_float_t*      out_float);

// Normalise a float image in-place (each channel gets `(x - mean) / std`).
ra_status_t ra_image_normalize(ra_image_float_t* image,
                                const float*      mean,
                                const float*      std);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------
void ra_image_free(ra_image_data_t* image);
void ra_image_float_free(ra_image_float_t* image);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_IMAGE_H
