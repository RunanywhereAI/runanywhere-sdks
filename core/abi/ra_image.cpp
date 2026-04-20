// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_image.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

namespace {

int32_t bytes_per_pixel(ra_vlm_image_format_t fmt) {
    switch (fmt) {
        case RA_VLM_IMAGE_FORMAT_RGB:
        case RA_VLM_IMAGE_FORMAT_BGR:
            return 3;
        case RA_VLM_IMAGE_FORMAT_RGBA:
        case RA_VLM_IMAGE_FORMAT_BGRA:
            return 4;
        default:
            return 0;
    }
}

ra_status_t alloc_image(ra_image_data_t* out, int32_t w, int32_t h,
                        ra_vlm_image_format_t fmt) {
    if (!out || w <= 0 || h <= 0) return RA_ERR_INVALID_ARGUMENT;
    const int32_t bpp = bytes_per_pixel(fmt);
    if (bpp == 0) return RA_ERR_INVALID_ARGUMENT;
    const std::size_t row = static_cast<std::size_t>(w) * bpp;
    const std::size_t total = row * static_cast<std::size_t>(h);
    out->data = static_cast<uint8_t*>(std::malloc(total));
    if (!out->data) return RA_ERR_OUT_OF_MEMORY;
    out->width = w; out->height = h; out->row_stride = static_cast<int32_t>(row);
    out->format = fmt;
    return RA_OK;
}

// Base64 decode (RFC 4648). Returns heap buffer + size.
uint8_t* base64_decode(std::string_view src, int32_t* out_size) {
    static constexpr int8_t T[256] = {
        // 0..63 valid bytes; -1 invalid; -2 padding '='; -3 whitespace.
        // Initialised below at runtime via lazy_init.
        0
    };
    static int8_t TBL[256];
    static bool   ready = false;
    if (!ready) {
        for (int i = 0; i < 256; ++i) TBL[i] = -1;
        const char* alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (int i = 0; i < 64; ++i) TBL[(unsigned char)alpha[i]] = static_cast<int8_t>(i);
        TBL[(unsigned char)'='] = -2;
        TBL[' '] = TBL['\n'] = TBL['\r'] = TBL['\t'] = -3;
        ready = true;
    }
    (void)T;
    std::size_t cap = (src.size() / 4) * 3 + 4;
    uint8_t* out = static_cast<uint8_t*>(std::malloc(cap));
    if (!out) return nullptr;
    int  buf  = 0;
    int  bits = 0;
    std::size_t n = 0;
    for (char c : src) {
        const int v = TBL[(unsigned char)c];
        if (v == -3) continue;
        if (v == -2) break;
        if (v == -1) { std::free(out); return nullptr; }
        buf = (buf << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[n++] = static_cast<uint8_t>((buf >> bits) & 0xFF);
        }
    }
    *out_size = static_cast<int32_t>(n);
    return out;
}

}  // namespace

extern "C" {

void ra_image_calc_resize(int32_t in_w, int32_t in_h, int32_t max_dim,
                          int32_t* out_w, int32_t* out_h) {
    if (!out_w || !out_h || in_w <= 0 || in_h <= 0 || max_dim <= 0) return;
    if (in_w <= max_dim && in_h <= max_dim) {
        *out_w = in_w; *out_h = in_h; return;
    }
    if (in_w >= in_h) {
        *out_w = max_dim;
        *out_h = static_cast<int32_t>(static_cast<int64_t>(in_h) * max_dim / in_w);
        if (*out_h <= 0) *out_h = 1;
    } else {
        *out_h = max_dim;
        *out_w = static_cast<int32_t>(static_cast<int64_t>(in_w) * max_dim / in_h);
        if (*out_w <= 0) *out_w = 1;
    }
}

ra_status_t ra_image_resize(const ra_image_data_t* in_image,
                             int32_t                 new_w,
                             int32_t                 new_h,
                             int32_t                 sampler,
                             ra_image_data_t*        out_image) {
    if (!in_image || !in_image->data || !out_image) return RA_ERR_INVALID_ARGUMENT;
    if (new_w <= 0 || new_h <= 0) return RA_ERR_INVALID_ARGUMENT;
    auto rc = alloc_image(out_image, new_w, new_h, in_image->format);
    if (rc != RA_OK) return rc;
    const int32_t bpp = bytes_per_pixel(in_image->format);
    const int32_t in_row = in_image->row_stride > 0 ? in_image->row_stride
                                                    : in_image->width * bpp;
    for (int32_t y = 0; y < new_h; ++y) {
        for (int32_t x = 0; x < new_w; ++x) {
            uint8_t* dst = out_image->data + y * out_image->row_stride + x * bpp;
            if (sampler == 1) {  // bilinear
                const float gx = (x + 0.5f) * in_image->width / new_w - 0.5f;
                const float gy = (y + 0.5f) * in_image->height / new_h - 0.5f;
                const int32_t x0 = std::clamp(static_cast<int32_t>(std::floor(gx)), 0, in_image->width - 1);
                const int32_t y0 = std::clamp(static_cast<int32_t>(std::floor(gy)), 0, in_image->height - 1);
                const int32_t x1 = std::min(x0 + 1, in_image->width - 1);
                const int32_t y1 = std::min(y0 + 1, in_image->height - 1);
                const float fx = std::clamp(gx - x0, 0.0f, 1.0f);
                const float fy = std::clamp(gy - y0, 0.0f, 1.0f);
                for (int32_t c = 0; c < bpp; ++c) {
                    const float p00 = in_image->data[y0 * in_row + x0 * bpp + c];
                    const float p10 = in_image->data[y0 * in_row + x1 * bpp + c];
                    const float p01 = in_image->data[y1 * in_row + x0 * bpp + c];
                    const float p11 = in_image->data[y1 * in_row + x1 * bpp + c];
                    const float top = p00 * (1 - fx) + p10 * fx;
                    const float bot = p01 * (1 - fx) + p11 * fx;
                    dst[c] = static_cast<uint8_t>(std::clamp(top * (1 - fy) + bot * fy, 0.0f, 255.0f));
                }
            } else {  // nearest
                const int32_t sx = std::clamp(x * in_image->width / new_w, 0, in_image->width - 1);
                const int32_t sy = std::clamp(y * in_image->height / new_h, 0, in_image->height - 1);
                std::memcpy(dst, in_image->data + sy * in_row + sx * bpp, bpp);
            }
        }
    }
    return RA_OK;
}

ra_status_t ra_image_resize_max(const ra_image_data_t* in_image,
                                 int32_t                 max_dim,
                                 int32_t                 sampler,
                                 ra_image_data_t*        out_image) {
    if (!in_image) return RA_ERR_INVALID_ARGUMENT;
    int32_t nw = 0, nh = 0;
    ra_image_calc_resize(in_image->width, in_image->height, max_dim, &nw, &nh);
    return ra_image_resize(in_image, nw, nh, sampler, out_image);
}

ra_status_t ra_image_convert_rgba_to_rgb(const ra_image_data_t* in_image,
                                          ra_image_data_t*       out_image) {
    if (!in_image || in_image->format != RA_VLM_IMAGE_FORMAT_RGBA) return RA_ERR_INVALID_ARGUMENT;
    auto rc = alloc_image(out_image, in_image->width, in_image->height, RA_VLM_IMAGE_FORMAT_RGB);
    if (rc != RA_OK) return rc;
    const int32_t in_row = in_image->row_stride > 0 ? in_image->row_stride : in_image->width * 4;
    for (int32_t y = 0; y < in_image->height; ++y) {
        const uint8_t* src = in_image->data + y * in_row;
        uint8_t* dst = out_image->data + y * out_image->row_stride;
        for (int32_t x = 0; x < in_image->width; ++x) {
            dst[x * 3 + 0] = src[x * 4 + 0];
            dst[x * 3 + 1] = src[x * 4 + 1];
            dst[x * 3 + 2] = src[x * 4 + 2];
        }
    }
    return RA_OK;
}

ra_status_t ra_image_convert_bgra_to_rgb(const ra_image_data_t* in_image,
                                          ra_image_data_t*       out_image) {
    if (!in_image || in_image->format != RA_VLM_IMAGE_FORMAT_BGRA) return RA_ERR_INVALID_ARGUMENT;
    auto rc = alloc_image(out_image, in_image->width, in_image->height, RA_VLM_IMAGE_FORMAT_RGB);
    if (rc != RA_OK) return rc;
    const int32_t in_row = in_image->row_stride > 0 ? in_image->row_stride : in_image->width * 4;
    for (int32_t y = 0; y < in_image->height; ++y) {
        const uint8_t* src = in_image->data + y * in_row;
        uint8_t* dst = out_image->data + y * out_image->row_stride;
        for (int32_t x = 0; x < in_image->width; ++x) {
            dst[x * 3 + 0] = src[x * 4 + 2];  // R from B
            dst[x * 3 + 1] = src[x * 4 + 1];
            dst[x * 3 + 2] = src[x * 4 + 0];  // B from R
        }
    }
    return RA_OK;
}

ra_status_t ra_image_to_chw(const ra_image_data_t* in_image,
                             const float*           mean,
                             const float*           std_arr,
                             int32_t                num_channels,
                             ra_image_float_t*      out_float) {
    if (!in_image || !out_float || num_channels <= 0) return RA_ERR_INVALID_ARGUMENT;
    const int32_t bpp = bytes_per_pixel(in_image->format);
    if (bpp < num_channels) return RA_ERR_INVALID_ARGUMENT;
    const int32_t in_row = in_image->row_stride > 0 ? in_image->row_stride : in_image->width * bpp;
    const std::size_t total = static_cast<std::size_t>(num_channels) * in_image->width * in_image->height;
    out_float->data = static_cast<float*>(std::malloc(total * sizeof(float)));
    if (!out_float->data) return RA_ERR_OUT_OF_MEMORY;
    out_float->width = in_image->width; out_float->height = in_image->height;
    out_float->channels = num_channels; out_float->channels_first = 1;
    for (int32_t c = 0; c < num_channels; ++c) {
        const float m = mean ? mean[c] : 0.0f;
        const float s = std_arr ? std_arr[c] : 1.0f;
        for (int32_t y = 0; y < in_image->height; ++y) {
            const uint8_t* src = in_image->data + y * in_row + c;
            float* dst = out_float->data + (c * in_image->height + y) * in_image->width;
            for (int32_t x = 0; x < in_image->width; ++x) {
                const float v = static_cast<float>(src[x * bpp]) / 255.0f;
                dst[x] = (v - m) / s;
            }
        }
    }
    return RA_OK;
}

ra_status_t ra_image_normalize(ra_image_float_t* image,
                                const float*      mean,
                                const float*      std_arr) {
    if (!image || !image->data) return RA_ERR_INVALID_ARGUMENT;
    const int32_t plane = image->width * image->height;
    for (int32_t c = 0; c < image->channels; ++c) {
        const float m = mean ? mean[c] : 0.0f;
        const float s = std_arr ? std_arr[c] : 1.0f;
        if (s == 0.0f) return RA_ERR_INVALID_ARGUMENT;
        float* base = image->channels_first ? (image->data + c * plane)
                                              : (image->data + c);
        const int32_t stride = image->channels_first ? 1 : image->channels;
        for (int32_t i = 0; i < plane; ++i) {
            float& v = base[i * stride];
            v = (v - m) / s;
        }
    }
    return RA_OK;
}

void ra_image_free(ra_image_data_t* image) {
    if (!image) return;
    if (image->data) { std::free(image->data); image->data = nullptr; }
    image->width = image->height = image->row_stride = 0;
}

void ra_image_float_free(ra_image_float_t* image) {
    if (!image) return;
    if (image->data) { std::free(image->data); image->data = nullptr; }
    image->width = image->height = image->channels = 0;
}

ra_status_t ra_image_decode_base64(const char* base64_text, ra_image_data_t* out_image) {
    if (!base64_text || !out_image) return RA_ERR_INVALID_ARGUMENT;
    int32_t size = 0;
    uint8_t* bytes = base64_decode(std::string_view{base64_text}, &size);
    if (!bytes) return RA_ERR_INVALID_ARGUMENT;
    auto rc = ra_image_decode_bytes(bytes, size, out_image);
    std::free(bytes);
    return rc;
}

// PNG/JPEG decoding requires a platform decoder; we do not bundle libpng/libjpeg.
// Frontends decode via Apple ImageIO / Android BitmapFactory / Web ImageBitmap
// and pass us the raw pixel buffer. Calling these without that path returns
// CAPABILITY_UNSUPPORTED so callers know to do the decode on their side.
ra_status_t ra_image_load_file(const char* /*path*/, ra_image_data_t* /*out_image*/) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

ra_status_t ra_image_decode_bytes(const uint8_t* /*bytes*/, int32_t /*size*/,
                                   ra_image_data_t* /*out_image*/) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

}  // extern "C"
