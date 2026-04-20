// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — VLM (vision-language model) C ABI.
//
// Mirrors LLM dispatch shape: every call routes through PluginRegistry +
// EngineRouter to pick a VLM-capable engine, then forwards through the
// engine's vtable VLM slots. Ports the legacy `rac_vlm_*` capability
// surface onto the new `ra_*` shape.

#ifndef RA_VLM_H
#define RA_VLM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Image input (passed by reference to ra_vlm_process / process_stream).
// `data` is RGB or RGBA pixel bytes; `format` indicates which.
// ---------------------------------------------------------------------------
typedef int32_t ra_vlm_image_format_t;
enum {
    RA_VLM_IMAGE_FORMAT_UNKNOWN = 0,
    RA_VLM_IMAGE_FORMAT_RGB     = 1,   // 3 bytes per pixel
    RA_VLM_IMAGE_FORMAT_RGBA    = 2,   // 4 bytes per pixel
    RA_VLM_IMAGE_FORMAT_BGR     = 3,
    RA_VLM_IMAGE_FORMAT_BGRA    = 4,
};

typedef int32_t ra_vlm_model_family_t;
enum {
    RA_VLM_FAMILY_UNKNOWN  = 0,
    RA_VLM_FAMILY_LLAVA    = 1,
    RA_VLM_FAMILY_QWEN_VL  = 2,
    RA_VLM_FAMILY_INTERNVL = 3,
    RA_VLM_FAMILY_PHI3V    = 4,
    RA_VLM_FAMILY_MOONDREAM = 5,
};

typedef struct ra_vlm_image_s {
    const uint8_t*       data;        // Pixel bytes
    int32_t              width;
    int32_t              height;
    int32_t              row_stride;  // 0 = width * bytes_per_pixel
    ra_vlm_image_format_t format;
} ra_vlm_image_t;

typedef struct ra_vlm_options_s {
    int32_t max_tokens;
    float   temperature;
    float   top_p;
    int32_t top_k;
    uint8_t stream;          // 0 = batch, non-zero = stream tokens
    uint8_t _reserved0[3];
    const char* system_prompt;  // Optional VLM-family-specific template override
} ra_vlm_options_t;

typedef struct ra_vlm_session_s ra_vlm_session_t;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------
ra_status_t ra_vlm_create(const ra_model_spec_t*     spec,
                          const ra_session_config_t* cfg,
                          ra_vlm_session_t**         out_session);

void        ra_vlm_destroy(ra_vlm_session_t* session);

// ---------------------------------------------------------------------------
// Inference — batch (returns full text) or streaming (callback).
// `out_text` heap-allocated; free with `ra_vlm_string_free`.
// ---------------------------------------------------------------------------
ra_status_t ra_vlm_process(ra_vlm_session_t*       session,
                           const ra_vlm_image_t*   image,
                           const char*             prompt,
                           const ra_vlm_options_t* options,
                           char**                  out_text);

ra_status_t ra_vlm_process_stream(ra_vlm_session_t*       session,
                                   const ra_vlm_image_t*  image,
                                   const char*            prompt,
                                   const ra_vlm_options_t* options,
                                   ra_token_callback_t    on_token,
                                   ra_error_callback_t    on_error,
                                   void*                  user_data);

ra_status_t ra_vlm_cancel(ra_vlm_session_t* session);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Returns the canonical built-in prompt template for the given VLM family
// (e.g. LLaVA's `USER:\n<image>\n{prompt}\nASSISTANT:`). Returns NULL when
// no template is known. The pointer is static and never freed.
const char* ra_vlm_get_builtin_template(ra_vlm_model_family_t family);

// Free a heap-allocated string returned by ra_vlm_process.
void ra_vlm_string_free(char* s);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_VLM_H
