// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — diffusion (text→image) C ABI.
//
// Mirrors LLM dispatch shape. Engines that don't serve diffusion leave
// the vtable slots NULL and the dispatch returns RA_ERR_CAPABILITY_UNSUPPORTED.
// Mobile platforms typically provide a CoreML / NPU-backed plugin; the
// core itself ships no diffusion engine.

#ifndef RA_DIFFUSION_H
#define RA_DIFFUSION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_diffusion_scheduler_t;
enum {
    RA_DIFFUSION_SCHEDULER_DEFAULT      = 0,
    RA_DIFFUSION_SCHEDULER_DDIM         = 1,
    RA_DIFFUSION_SCHEDULER_DPMSOLVER    = 2,
    RA_DIFFUSION_SCHEDULER_EULER        = 3,
    RA_DIFFUSION_SCHEDULER_EULER_ANCESTRAL = 4,
};

typedef struct ra_diffusion_config_s {
    int32_t                 width;
    int32_t                 height;
    int32_t                 num_inference_steps;
    float                   guidance_scale;
    int64_t                 seed;            // -1 = random
    ra_diffusion_scheduler_t scheduler;
    uint8_t                 enable_safety_checker;
    uint8_t                 _reserved0[3];
} ra_diffusion_config_t;

typedef struct ra_diffusion_options_s {
    const char* negative_prompt;     // Optional
    int32_t     num_images;          // Default 1
    int32_t     batch_size;          // 0 = auto
} ra_diffusion_options_t;

typedef struct ra_diffusion_session_s ra_diffusion_session_t;

typedef void (*ra_diffusion_progress_callback_t)(int32_t step, int32_t total,
                                                  void* user_data);

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------
ra_status_t ra_diffusion_create(const ra_model_spec_t*       spec,
                                 const ra_diffusion_config_t* cfg,
                                 ra_diffusion_session_t**     out_session);

void        ra_diffusion_destroy(ra_diffusion_session_t* session);

// Generate `num_images` PNG-encoded images (concatenated PNG chunks NOT a
// real PNG; first 4 bytes of `out_png_bytes` give the size of the first
// image; convenience implementations may return one image at a time).
//
// `out_png_bytes` is heap-allocated; caller MUST free with `ra_diffusion_bytes_free`.
ra_status_t ra_diffusion_generate(ra_diffusion_session_t*       session,
                                   const char*                   prompt,
                                   const ra_diffusion_options_t* options,
                                   uint8_t**                     out_png_bytes,
                                   int32_t*                      out_size);

// Same as ra_diffusion_generate, but invokes `progress_cb` once per
// inference step (cb may be NULL).
ra_status_t ra_diffusion_generate_with_progress(
    ra_diffusion_session_t*           session,
    const char*                       prompt,
    const ra_diffusion_options_t*     options,
    ra_diffusion_progress_callback_t  progress_cb,
    void*                             user_data,
    uint8_t**                         out_png_bytes,
    int32_t*                          out_size);

ra_status_t ra_diffusion_cancel(ra_diffusion_session_t* session);

// Memory ownership.
void ra_diffusion_bytes_free(uint8_t* bytes);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_DIFFUSION_H
