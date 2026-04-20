// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — platform-LLM callback table.
//
// Lets the platform bridge plug in native LLM frameworks that have no C++
// implementation we can compile in directly: Apple Foundation Models on
// iOS 18+, Qualcomm Genie on Android, etc. The frontend supplies callbacks
// that the core invokes when it routes an LLM request to that backend.

#ifndef RA_PLATFORM_LLM_H
#define RA_PLATFORM_LLM_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_platform_llm_backend_t;
enum {
    RA_PLATFORM_LLM_UNKNOWN          = 0,
    RA_PLATFORM_LLM_FOUNDATION_MODELS = 1,  // Apple iOS/macOS
    RA_PLATFORM_LLM_GENIE            = 2,    // Qualcomm Snapdragon
    RA_PLATFORM_LLM_GEMINI_NANO      = 3,    // Android AICore
    RA_PLATFORM_LLM_OPENVINO         = 4,    // Intel
};

typedef struct ra_platform_llm_session_s ra_platform_llm_session_t;

typedef struct ra_platform_llm_callbacks_s {
    // Returns 1 if this backend can serve the supplied model spec.
    uint8_t (*can_handle)(const ra_model_spec_t* spec, void* user_data);

    // Lifecycle
    ra_status_t (*create)(const ra_model_spec_t* spec,
                           const ra_session_config_t* cfg,
                           ra_platform_llm_session_t** out_session,
                           void* user_data);
    void        (*destroy)(ra_platform_llm_session_t* session, void* user_data);

    // Generation
    ra_status_t (*generate)(ra_platform_llm_session_t* session,
                             const ra_prompt_t*         prompt,
                             ra_token_callback_t        on_token,
                             ra_error_callback_t        on_error,
                             void*                      callback_user_data,
                             void*                      user_data);
    ra_status_t (*cancel)(ra_platform_llm_session_t* session, void* user_data);

    void* user_data;
} ra_platform_llm_callbacks_t;

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
ra_status_t ra_platform_llm_set_callbacks(ra_platform_llm_backend_t backend,
                                           const ra_platform_llm_callbacks_t* callbacks);

const ra_platform_llm_callbacks_t* ra_platform_llm_get_callbacks(
    ra_platform_llm_backend_t backend);

// Returns 1 if `backend` is currently registered AND its can_handle gate
// (if any) passes for the supplied spec.
uint8_t ra_platform_llm_is_available(ra_platform_llm_backend_t backend,
                                      const ra_model_spec_t* spec);

// Forward dispatch helpers — used by `ra_llm_dispatch` when it picks a
// platform-LLM backend.
ra_status_t ra_platform_llm_create(ra_platform_llm_backend_t backend,
                                    const ra_model_spec_t*    spec,
                                    const ra_session_config_t* cfg,
                                    ra_platform_llm_session_t** out_session);

void        ra_platform_llm_destroy(ra_platform_llm_backend_t backend,
                                      ra_platform_llm_session_t* session);

ra_status_t ra_platform_llm_generate(ra_platform_llm_backend_t backend,
                                       ra_platform_llm_session_t* session,
                                       const ra_prompt_t*         prompt,
                                       ra_token_callback_t        on_token,
                                       ra_error_callback_t        on_error,
                                       void*                      user_data);

// Register / unregister a platform-LLM backend with the global registry.
ra_status_t ra_backend_platform_register(ra_platform_llm_backend_t backend);
ra_status_t ra_backend_platform_unregister(ra_platform_llm_backend_t backend);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PLATFORM_LLM_H
