// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Swift ↔ engine-plugin bridge declarations. Engine plugins living in
// `engines/<name>/` define their own internal bridge header, but the
// corresponding frontend-visible set_callbacks entry points are
// forward-declared here so that the Swift XCFramework module can reach
// them without exporting each engine's internal header.

#ifndef RA_BACKENDS_H
#define RA_BACKENDS_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// WhisperKit STT Swift bridge. Defined in engines/whisperkit/.
// Mirrors `ra_whisperkit_callbacks_t` from whisperkit_bridge.h.
// ---------------------------------------------------------------------------

typedef struct ra_whisperkit_session_s* ra_whisperkit_session_handle_t;

typedef struct ra_whisperkit_callbacks_s {
    ra_whisperkit_session_handle_t (*create)(const char* model_path, void* user_data);
    void (*destroy)(ra_whisperkit_session_handle_t handle, void* user_data);
    ra_status_t (*transcribe)(ra_whisperkit_session_handle_t handle,
                                const float* audio,
                                size_t       sample_count,
                                int32_t      sample_rate_hz,
                                const char*  language,
                                char**       out_utf8_text,
                                void*        user_data);
    void (*string_free)(char* str, void* user_data);
    void* user_data;
} ra_whisperkit_callbacks_t;

ra_status_t ra_whisperkit_set_callbacks(
    const ra_whisperkit_callbacks_t* callbacks);

uint8_t ra_whisperkit_has_callbacks(void);

// ---------------------------------------------------------------------------
// CoreML Stable Diffusion Swift bridge. Defined in engines/diffusion-coreml/.
// The ml-stable-diffusion SPM package lives on the Swift side.
// ---------------------------------------------------------------------------

typedef struct ra_diffusion_coreml_session_s* ra_diffusion_coreml_handle_t;

typedef struct ra_diffusion_coreml_callbacks_s {
    // create(model_folder, compute_units, user_data) → handle or nullptr.
    // compute_units: 0=cpuAndGPU, 1=cpuAndNeuralEngine, 2=all.
    ra_diffusion_coreml_handle_t (*create)(const char* model_folder,
                                             int32_t     compute_units,
                                             void*       user_data);

    void (*destroy)(ra_diffusion_coreml_handle_t handle, void* user_data);

    // generate(handle, prompt, negative_prompt, seed, steps, guidance,
    //          image_width, image_height, on_step, on_step_ud,
    //          out_png_bytes, out_size, user_data). out_png_bytes is
    // malloc-allocated by Swift, freed via bytes_free callback.
    ra_status_t (*generate)(ra_diffusion_coreml_handle_t handle,
                              const char*  prompt,
                              const char*  negative_prompt,
                              int64_t      seed,
                              int32_t      steps,
                              float        guidance_scale,
                              int32_t      image_width,
                              int32_t      image_height,
                              void (*on_step)(int32_t step, int32_t total, void* ud),
                              void*        on_step_ud,
                              uint8_t**    out_png_bytes,
                              int32_t*     out_size,
                              void*        user_data);

    ra_status_t (*cancel)(ra_diffusion_coreml_handle_t handle, void* user_data);

    // bytes_free(ptr, user_data) — free buffers returned by generate.
    void (*bytes_free)(uint8_t* ptr, void* user_data);

    void* user_data;
} ra_diffusion_coreml_callbacks_t;

ra_status_t ra_diffusion_coreml_set_callbacks(
    const ra_diffusion_coreml_callbacks_t* callbacks);

uint8_t ra_diffusion_coreml_has_callbacks(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_BACKENDS_H
