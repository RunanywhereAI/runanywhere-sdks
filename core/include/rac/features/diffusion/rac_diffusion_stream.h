/**
 * @file rac_diffusion_stream.h
 * @brief Lifecycle-owned proto-byte DiffusionStreamEvent ABI for streaming
 *        image-generation sessions.
 *
 * Mirrors the LLM streaming pattern declared in `rac_llm_stream.h`. The
 * canonical SDK-facing flow is:
 *
 *   1. SDK registers a single proto-byte callback per diffusion handle via
 *      `rac_diffusion_set_stream_proto_callback()`.
 *   2. SDK starts an image generation session via
 *      `rac_diffusion_stream_start_proto()` with serialized
 *      `runanywhere.v1.DiffusionGenerationRequest` bytes. C++ returns a
 *      session id; lifecycle manager tracks it.
 *   3. The diffusion engine emits progress, optional intermediate images,
 *      and a terminal completion event as serialized
 *      `runanywhere.v1.DiffusionStreamEvent` bytes on the registered
 *      callback.
 *   4. SDK terminates via `rac_diffusion_stream_stop_proto()` (drain) or
 *      `rac_diffusion_stream_cancel_proto()` (immediate teardown).
 *
 * Lifetime: the buffer passed to the callback is valid only for the
 * duration of the callback invocation. Retainers must copy the bytes out.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `SDK-facing default`.
 */

#ifndef RAC_FEATURES_DIFFUSION_RAC_DIFFUSION_STREAM_H
#define RAC_FEATURES_DIFFUSION_RAC_DIFFUSION_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Callback fired once per `runanywhere.v1.DiffusionStreamEvent`
 *        with serialized proto bytes.
 */
typedef void (*rac_diffusion_stream_proto_callback_fn)(const uint8_t* event_bytes,
                                                       size_t event_size, void* user_data);

/**
 * @brief Register a proto-byte stream callback on a diffusion component
 *        handle.
 *
 * One registration per handle. Calling again replaces the previous slot.
 * Pass NULL to clear.
 *
 * @warning user_data ownership and lifetime (cross-SDK
 *          contract — see rac_llm_stream.h for the canonical recipe). The C
 *          runtime may invoke `callback(bytes, size, user_data)` on a
 *          background thread AFTER
 *          rac_diffusion_unset_stream_proto_callback(handle) has returned,
 *          because the dispatcher copies the callback slot under its
 *          internal mutex and releases the mutex BEFORE invoking the user
 *          callback (see rac_diffusion_stream.cpp
 *          lock-release-before-callback comment). The caller MUST ensure no
 *          in-flight invocation is executing on a background thread before
 *          freeing @p user_data.
 *
 *          Recommended teardown sequence:
 *            (a) call rac_diffusion_unset_stream_proto_callback(handle) —
 *                clears the slot atomically so no NEW dispatches will fire;
 *            (b) call rac_diffusion_proto_quiesce() — cancels active
 *                generations and blocks until every in-flight callback
 *                invocation has returned;
 *            (c) free @p user_data.
 *
 *          Modalities that currently expose proto_quiesce: LLM
 *          (rac_llm_stream.h), STT (rac_stt_stream.h), TTS
 *          (rac_tts_stream.h), VAD (rac_vad_stream.h), Diffusion (this
 *          header), VLM (rac_vlm_service.h). voice_agent quiesces in-flight
 *          callbacks as part of rac_voice_agent_destroy() rather than
 *          exposing a standalone quiesce entry point. SDK fan-out helpers
 *          (Swift HandleStreamAdapter, Kotlin/Flutter/RN equivalents)
 *          centralize this dance for their host language; refer to the
 *          canonical adapter implementation when porting a new SDK.
 */
RAC_API rac_result_t rac_diffusion_set_stream_proto_callback(
    rac_handle_t handle, rac_diffusion_stream_proto_callback_fn callback, void* user_data);

/**
 * @brief Unregister the proto-byte stream callback for a handle.
 */
RAC_API rac_result_t rac_diffusion_unset_stream_proto_callback(rac_handle_t handle);

/**
 * @brief Cancel any in-flight diffusion generations, then block (without
 *        busy-spinning) until every in-flight proto-byte stream dispatch and
 *        worker has drained. Mirrors rac_vlm_proto_quiesce /
 *        rac_llm_proto_quiesce, but additionally cancels active generations so
 *        teardown returns promptly instead of waiting out a full 30-60s image.
 *        Callers freeing user_data passed into
 *        rac_diffusion_set_stream_proto_callback, or tearing down the
 *        diffusion component / swapping the model, should call this after the
 *        unset before freeing the user_data. Safe to call from any thread.
 */
RAC_API void rac_diffusion_proto_quiesce(void);

/**
 * @brief Start a streaming diffusion image-generation session.
 *
 * @retval RAC_SUCCESS                     Session started.
 * @retval RAC_ERROR_INVALID_HANDLE        @p handle is null or invalid.
 * @retval RAC_ERROR_NULL_POINTER          @p out_session_id is null.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE Library was built without Protobuf.
 * @retval RAC_ERROR_NOT_IMPLEMENTED       Session backend not yet wired (stub).
 */
RAC_API rac_result_t rac_diffusion_stream_start_proto(rac_handle_t handle,
                                                      const uint8_t* request_proto_bytes,
                                                      size_t request_proto_size,
                                                      uint64_t* out_session_id);

/**
 * @brief Stop a diffusion streaming session (graceful drain).
 *
 * Lets the in-flight generation run to completion and deliver its terminal
 * COMPLETED event; the session's handle frees once that generation finishes.
 * Use rac_diffusion_stream_cancel_proto() for immediate teardown.
 */
RAC_API rac_result_t rac_diffusion_stream_stop_proto(uint64_t session_id);

/**
 * @brief Cancel a diffusion streaming session immediately.
 *
 * Aborts the in-flight generation, frees the handle for reuse right away, and
 * delivers a terminal ERROR (cancelled) event to the registered callback.
 */
RAC_API rac_result_t rac_diffusion_stream_cancel_proto(uint64_t session_id);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_DIFFUSION_RAC_DIFFUSION_STREAM_H */
