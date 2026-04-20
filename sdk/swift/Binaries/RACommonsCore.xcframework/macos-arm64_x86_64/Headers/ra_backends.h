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

// ---------------------------------------------------------------------------
// MetalRT Swift bridge. Defined in engines/metalrt/. MetalRT is an
// Apple-internal closed-source SDK (`MetalRT.framework`); when
// unavailable, the plugin no-ops. Swift side is optional.
// ---------------------------------------------------------------------------

typedef struct ra_metalrt_llm_session_s* ra_metalrt_llm_handle_t;

typedef struct ra_metalrt_callbacks_s {
    ra_metalrt_llm_handle_t (*create)(const char* model_path, void* user_data);
    void        (*destroy)(ra_metalrt_llm_handle_t handle, void* user_data);
    ra_status_t (*generate)(ra_metalrt_llm_handle_t handle,
                              const char* prompt,
                              void (*on_token)(const char* text, int32_t is_final, void* ud),
                              void* on_token_ud,
                              void* user_data);
    ra_status_t (*cancel)(ra_metalrt_llm_handle_t handle, void* user_data);
    void* user_data;
} ra_metalrt_callbacks_t;

ra_status_t ra_metalrt_set_callbacks(const ra_metalrt_callbacks_t* callbacks);
uint8_t     ra_metalrt_has_callbacks(void);

// ---------------------------------------------------------------------------
// ONNX Runtime Swift/Kotlin bridge. Defined in engines/onnx/. When the
// native ORT library isn't linked, frontends can still provide LLM /
// embedding / STT via this callback table.
// ---------------------------------------------------------------------------

typedef struct ra_onnx_llm_session_s*   ra_onnx_llm_handle_t;
typedef struct ra_onnx_embed_session_s* ra_onnx_embed_handle_t;
typedef struct ra_onnx_stt_session_s*   ra_onnx_stt_handle_t;

typedef struct ra_onnx_callbacks_s {
    // LLM slot.
    ra_onnx_llm_handle_t (*llm_create)(const char* model_path, void* user_data);
    void                 (*llm_destroy)(ra_onnx_llm_handle_t handle, void* user_data);
    ra_status_t          (*llm_generate)(ra_onnx_llm_handle_t handle,
                                           const char* prompt,
                                           void (*on_token)(const char* text, int32_t is_final, void* ud),
                                           void* on_token_ud,
                                           void* user_data);
    ra_status_t          (*llm_cancel)(ra_onnx_llm_handle_t handle, void* user_data);

    // Embedding slot.
    ra_onnx_embed_handle_t (*embed_create)(const char* model_path, void* user_data);
    void                   (*embed_destroy)(ra_onnx_embed_handle_t handle, void* user_data);
    ra_status_t            (*embed_encode)(ra_onnx_embed_handle_t handle,
                                              const char* text,
                                              float** out_vector, int32_t* out_dim,
                                              void* user_data);
    void                   (*embed_floats_free)(float* v, void* user_data);

    // STT slot — optional. Null fields report CAPABILITY_UNSUPPORTED.
    ra_onnx_stt_handle_t (*stt_create)(const char* model_path, void* user_data);
    void                 (*stt_destroy)(ra_onnx_stt_handle_t handle, void* user_data);
    ra_status_t          (*stt_transcribe)(ra_onnx_stt_handle_t handle,
                                              const float* audio, size_t samples,
                                              int32_t sample_rate,
                                              char** out_utf8_text,
                                              void* user_data);
    void                 (*stt_string_free)(char* str, void* user_data);

    void* user_data;
} ra_onnx_callbacks_t;

ra_status_t ra_onnx_set_callbacks(const ra_onnx_callbacks_t* callbacks);
uint8_t     ra_onnx_has_callbacks(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_BACKENDS_H
