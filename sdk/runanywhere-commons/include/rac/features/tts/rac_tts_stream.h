/**
 * @file rac_tts_stream.h
 * @brief Lifecycle-owned proto-byte TTSStreamEvent ABI for streaming
 *        text-to-speech sessions.
 *
 * Mirrors the LLM streaming pattern declared in `rac_llm_stream.h`. The
 * canonical SDK-facing flow is:
 *
 *   1. SDK registers a single proto-byte callback per TTS component handle
 *      via `rac_tts_set_stream_proto_callback()`.
 *   2. SDK starts a streaming synthesis by calling
 *      `rac_tts_stream_start_proto()` with serialized
 *      `runanywhere.v1.TTSSynthesisRequest` bytes (text + options).
 *      C++ returns a session id which is owned by the lifecycle manager —
 *      unloading the voice cancels active sessions.
 *   3. The synthesis runs asynchronously; chunks, phoneme timestamps, and
 *      completion events arrive on the registered stream callback as
 *      serialized `runanywhere.v1.TTSStreamEvent` bytes.
 *   4. SDK terminates the session via `rac_tts_stream_stop_proto()` (drain
 *      pending events) or `rac_tts_stream_cancel_proto()` (immediate
 *      teardown).
 *
 * Lifetime: the buffer passed to the callback is valid only for the
 * duration of the callback invocation. Retainers must copy the bytes out.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `SDK-facing default`.
 */

#ifndef RAC_FEATURES_TTS_RAC_TTS_STREAM_H
#define RAC_FEATURES_TTS_RAC_TTS_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Callback fired once per `runanywhere.v1.TTSStreamEvent` with
 *        serialized proto bytes.
 */
typedef void (*rac_tts_stream_proto_callback_fn)(const uint8_t* event_bytes, size_t event_size,
                                                 void* user_data);

/**
 * @brief Register a proto-byte stream callback on a TTS component handle.
 *
 * One registration per handle. Calling again replaces the previous slot.
 * Pass NULL to clear.
 */
RAC_API rac_result_t rac_tts_set_stream_proto_callback(rac_handle_t handle,
                                                       rac_tts_stream_proto_callback_fn callback,
                                                       void* user_data);

/**
 * @brief Unregister the proto-byte stream callback for a handle.
 */
RAC_API rac_result_t rac_tts_unset_stream_proto_callback(rac_handle_t handle);

/**
 * @brief Start a streaming TTS synthesis session.
 *
 * @p request_proto_bytes encodes a serialized
 * `runanywhere.v1.TTSSynthesisRequest` carrying both the text and the
 * synthesis options.
 *
 * @retval RAC_SUCCESS                     Session started.
 * @retval RAC_ERROR_INVALID_HANDLE        @p handle is null or invalid.
 * @retval RAC_ERROR_NULL_POINTER          @p out_session_id is null.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE Library was built without Protobuf.
 * @retval RAC_ERROR_NOT_IMPLEMENTED       Session backend not yet wired (stub).
 */
RAC_API rac_result_t rac_tts_stream_start_proto(rac_handle_t handle,
                                                const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                uint64_t* out_session_id);

/**
 * @brief Stop a TTS streaming session, flushing pending audio events.
 */
RAC_API rac_result_t rac_tts_stream_stop_proto(uint64_t session_id);

/**
 * @brief Cancel a TTS streaming session immediately.
 *
 * Drops any in-flight audio chunks. No further events delivered.
 */
RAC_API rac_result_t rac_tts_stream_cancel_proto(uint64_t session_id);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_TTS_RAC_TTS_STREAM_H */
