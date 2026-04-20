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

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_BACKENDS_H
