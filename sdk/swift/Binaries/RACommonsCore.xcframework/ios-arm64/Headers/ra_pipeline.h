// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — stable C ABI for pipeline lifecycle.
//
// This ABI uses plain C structs (NOT proto3 bytes) so frontends do not need
// to link a protobuf runtime. The matching proto3 schemas in idl/*.proto are
// the canonical IDL; this header is a 1:1 C mirror of the subset frontends
// actually use.
//
// The C ABI NEVER takes ownership of caller buffers and NEVER hands out
// pointers that outlive the callback. Callers must copy bytes they need to
// retain.

#ifndef RA_PIPELINE_H
#define RA_PIPELINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"
#include "ra_version.h"

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pipeline handle — one instance per active session.
typedef struct ra_pipeline_s ra_pipeline_t;

// ---------------------------------------------------------------------------
// Solution configs — mirrors idl/solutions.proto
// ---------------------------------------------------------------------------

typedef int32_t ra_audio_source_t;
enum {
    RA_AUDIO_SOURCE_UNSPECIFIED = 0,
    RA_AUDIO_SOURCE_MICROPHONE  = 1,
    RA_AUDIO_SOURCE_FILE        = 2,
    RA_AUDIO_SOURCE_CALLBACK    = 3,
};

typedef struct {
    const char*       llm_model_id;
    const char*       stt_model_id;
    const char*       tts_model_id;
    const char*       vad_model_id;

    int32_t           sample_rate_hz;          // default 16000
    int32_t           chunk_ms;                // default 20
    ra_audio_source_t audio_source;

    const char*       audio_file_path;         // NULL unless FILE source

    uint8_t           enable_barge_in;         // 0 / non-zero
    int32_t           barge_in_threshold_ms;   // default 200

    const char*       system_prompt;           // may be NULL
    int32_t           max_context_tokens;
    float             temperature;

    uint8_t           emit_partials;
    uint8_t           emit_thoughts;
    uint8_t           _reserved0[2];
} ra_voice_agent_config_t;

// ---------------------------------------------------------------------------
// Streaming events — mirrors idl/voice_events.proto
// ---------------------------------------------------------------------------

typedef int32_t ra_voice_event_kind_t;
enum {
    RA_VOICE_EVENT_UNKNOWN         = 0,
    RA_VOICE_EVENT_USER_SAID       = 1,
    RA_VOICE_EVENT_ASSISTANT_TOKEN = 2,
    RA_VOICE_EVENT_AUDIO           = 3,
    RA_VOICE_EVENT_VAD             = 4,
    RA_VOICE_EVENT_INTERRUPTED     = 5,
    RA_VOICE_EVENT_STATE_CHANGE    = 6,
    RA_VOICE_EVENT_ERROR           = 7,
    RA_VOICE_EVENT_METRICS         = 8,
};

typedef int32_t ra_pipeline_state_t;
enum {
    RA_PIPELINE_STATE_UNSPECIFIED = 0,
    RA_PIPELINE_STATE_IDLE        = 1,
    RA_PIPELINE_STATE_LISTENING   = 2,
    RA_PIPELINE_STATE_THINKING    = 3,
    RA_PIPELINE_STATE_SPEAKING    = 4,
    RA_PIPELINE_STATE_STOPPED     = 5,
};

typedef struct {
    ra_voice_event_kind_t kind;
    uint64_t              seq;

    // Populated when kind == USER_SAID / ASSISTANT_TOKEN / INTERRUPTED / ERROR.
    const char*           text;        // null-terminated, owned by core
    uint8_t               is_final;    // USER_SAID / ASSISTANT_TOKEN
    uint8_t               _reserved0[3];
    int32_t               token_kind;  // 1=answer, 2=thought, 3=tool_call
    ra_vad_event_type_t   vad_type;    // kind == VAD

    // Populated when kind == AUDIO.
    const float*          pcm_f32;
    int32_t               pcm_len;
    int32_t               sample_rate_hz;

    // Populated when kind == STATE_CHANGE.
    ra_pipeline_state_t   prev_state;
    ra_pipeline_state_t   curr_state;

    // Populated when kind == METRICS.
    double                stt_final_ms;
    double                llm_first_token_ms;
    double                tts_first_audio_ms;
    double                end_to_end_ms;

    // Populated when kind == ERROR.
    int32_t               error_code;
} ra_voice_event_t;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

typedef void (*ra_voice_event_callback_t)(const ra_voice_event_t* event,
                                           void* user_data);

typedef void (*ra_completion_callback_t)(ra_status_t status,
                                          const char* message,
                                          void* user_data);

// ---------------------------------------------------------------------------
// Pipeline lifecycle
// ---------------------------------------------------------------------------

ra_status_t ra_pipeline_create_voice_agent(const ra_voice_agent_config_t* config,
                                            ra_pipeline_t** out_pipeline);

void ra_pipeline_destroy(ra_pipeline_t* pipeline);

ra_status_t ra_pipeline_set_event_callback(ra_pipeline_t*            pipeline,
                                            ra_voice_event_callback_t callback,
                                            void*                     user_data);

ra_status_t ra_pipeline_set_completion_callback(
    ra_pipeline_t*           pipeline,
    ra_completion_callback_t callback,
    void*                    user_data);

ra_status_t ra_pipeline_run(ra_pipeline_t* pipeline);
ra_status_t ra_pipeline_cancel(ra_pipeline_t* pipeline);

ra_status_t ra_pipeline_feed_audio(ra_pipeline_t* pipeline,
                                    const float*   pcm_f32,
                                    int32_t        num_samples,
                                    int32_t        sample_rate_hz);

// Injects a barge-in control signal (simulated user interruption).
ra_status_t ra_pipeline_inject_barge_in(ra_pipeline_t* pipeline);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PIPELINE_H
