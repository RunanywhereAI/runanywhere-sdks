// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — stable C ABI for pipeline lifecycle.
//
// This ABI carries proto3-encoded messages across the boundary. The byte
// buffers are serialized VoiceEvent / PipelineSpec / SolutionConfig messages.
// Frontends decode them with their native proto3 runtime (swift-protobuf,
// Wire, protobuf.dart, ts-proto) — there is NO hand-written event struct in
// any frontend.
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
// Callback fired for every VoiceEvent emitted by the pipeline.
//
// `event_bytes` / `event_len` is a serialized runanywhere.v1.VoiceEvent
// message. The memory is owned by the core and is valid ONLY for the
// duration of the callback; copy before returning if you need to retain.
//
// `user_data` is the pointer passed at ra_pipeline_create.
// ---------------------------------------------------------------------------
typedef void (*ra_event_callback_t)(const uint8_t* event_bytes,
                                    size_t         event_len,
                                    void*          user_data);

// ---------------------------------------------------------------------------
// Callback fired when the pipeline terminates (normal completion, cancel, or
// error). After this fires, no further event callbacks will fire, and the
// pipeline handle may be destroyed.
//
// When `status == RA_OK`, the pipeline completed normally.
// When non-zero, `message` contains a human-readable description.
// ---------------------------------------------------------------------------
typedef void (*ra_completion_callback_t)(ra_status_t status,
                                         const char* message,
                                         void*       user_data);

// ---------------------------------------------------------------------------
// Create a pipeline from a serialized runanywhere.v1.PipelineSpec.
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_create(const uint8_t* spec_bytes,
                               size_t         spec_len,
                               ra_pipeline_t** out_pipeline);

// Create a pipeline from a serialized runanywhere.v1.SolutionConfig.
// The core maps the solution config to a PipelineSpec internally.
ra_status_t ra_pipeline_create_from_solution(const uint8_t*  config_bytes,
                                             size_t          config_len,
                                             ra_pipeline_t** out_pipeline);

// Destroy the pipeline. MUST be called after completion callback fires.
// Calling this while the pipeline is running is undefined behavior; call
// ra_pipeline_cancel first and wait for the completion callback.
void ra_pipeline_destroy(ra_pipeline_t* pipeline);

// ---------------------------------------------------------------------------
// Register an event callback. Must be called before ra_pipeline_run. Only
// one callback per pipeline; subsequent calls replace the previous one.
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_set_event_callback(ra_pipeline_t*      pipeline,
                                           ra_event_callback_t callback,
                                           void*               user_data);

// Register a completion callback. Optional; if unset, termination is silent.
ra_status_t ra_pipeline_set_completion_callback(
    ra_pipeline_t*           pipeline,
    ra_completion_callback_t callback,
    void*                    user_data);

// ---------------------------------------------------------------------------
// Start the pipeline. Runs asynchronously on a core-owned thread (GCD queue
// on iOS, Asio io_context elsewhere, event loop on WASM). Returns immediately.
// Events arrive via the event callback until terminated.
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_run(ra_pipeline_t* pipeline);

// ---------------------------------------------------------------------------
// Request cancellation. Thread-safe. The completion callback fires with
// RA_ERR_CANCELLED after graceful teardown.
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_cancel(ra_pipeline_t* pipeline);

// ---------------------------------------------------------------------------
// Feed an externally-captured audio frame — used when the solution config
// specifies AUDIO_SOURCE_CALLBACK. No-op for AUDIO_SOURCE_MICROPHONE.
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_feed_audio(ra_pipeline_t* pipeline,
                                   const float*   pcm_f32,
                                   int32_t        num_samples,
                                   int32_t        sample_rate_hz);

// ---------------------------------------------------------------------------
// Inject a control event (e.g. user-initiated barge-in from a UI button).
// `event_bytes` is a serialized runanywhere.v1.VoiceEvent (usually a VADEvent).
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_inject_event(ra_pipeline_t* pipeline,
                                     const uint8_t* event_bytes,
                                     size_t         event_len);

// ---------------------------------------------------------------------------
// Validate a PipelineSpec without running it. Returns RA_OK if the DAG is
// well-formed and every referenced operator / engine is registered. On
// failure, `out_message` (if non-NULL) receives a human-readable explanation
// written into `out_message_cap` bytes; `out_message_len` receives the
// actual number of bytes written (excluding null terminator).
// ---------------------------------------------------------------------------
ra_status_t ra_pipeline_validate(const uint8_t* spec_bytes,
                                 size_t         spec_len,
                                 char*          out_message,
                                 size_t         out_message_cap,
                                 size_t*        out_message_len);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PIPELINE_H
