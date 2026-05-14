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
 */
RAC_API rac_result_t rac_diffusion_set_stream_proto_callback(
    rac_handle_t handle, rac_diffusion_stream_proto_callback_fn callback, void* user_data);

/**
 * @brief Unregister the proto-byte stream callback for a handle.
 */
RAC_API rac_result_t rac_diffusion_unset_stream_proto_callback(rac_handle_t handle);

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
 * @brief Stop a diffusion streaming session, flushing pending events.
 */
RAC_API rac_result_t rac_diffusion_stream_stop_proto(uint64_t session_id);

/**
 * @brief Cancel a diffusion streaming session immediately.
 */
RAC_API rac_result_t rac_diffusion_stream_cancel_proto(uint64_t session_id);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_DIFFUSION_RAC_DIFFUSION_STREAM_H */
