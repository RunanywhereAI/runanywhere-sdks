/**
 * @file rac_stt_stream.h
 * @brief Lifecycle-owned proto-byte STTStreamEvent ABI for streaming
 *        speech-to-text sessions.
 *
 * Mirrors the LLM streaming pattern declared in `rac_llm_stream.h`. The
 * canonical SDK-facing flow is:
 *
 *   1. SDK registers a single proto-byte callback per STT component handle
 *      via `rac_stt_set_stream_proto_callback()`.
 *   2. SDK starts a session by calling `rac_stt_stream_start_proto()` with
 *      a serialized `runanywhere.v1.STTOptions` payload. C++ returns a
 *      session id which is owned by the lifecycle manager — unloading
 *      the model cancels active sessions.
 *   3. SDK feeds audio frames via `rac_stt_stream_feed_audio_proto()`.
 *      Each accepted frame produces zero or more `STTStreamEvent` proto
 *      bytes routed to the registered callback.
 *   4. SDK terminates the session via `rac_stt_stream_stop_proto()` (drain
 *      pending events) or `rac_stt_stream_cancel_proto()` (immediately
 *      suppress new events, then drain already-accepted provider work).
 *
 * Lifetime: the buffer passed to the callback is valid only for the
 * duration of the callback invocation. Callers that retain bytes MUST
 * copy them out — the C++ side reuses thread-local scratch buffers and
 * an arena-backed proto message across events.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `SDK-facing default`.
 * The legacy struct callback path remains for backend smoke tests; SDKs
 * MUST migrate to this proto-byte stream ABI.
 */

#ifndef RAC_FEATURES_STT_RAC_STT_STREAM_H
#define RAC_FEATURES_STT_RAC_STT_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Callback fired once per `runanywhere.v1.STTStreamEvent` with
 *        serialized proto bytes.
 *
 * @param event_bytes Pointer to `STTStreamEvent.SerializeToArray(...)` output.
 * @param event_size  Number of valid bytes at @p event_bytes.
 * @param user_data   Opaque pointer registered with
 *                    rac_stt_set_stream_proto_callback().
 *
 * See file header for lifetime constraints on @p event_bytes.
 */
typedef void (*rac_stt_stream_proto_callback_fn)(const uint8_t* event_bytes, size_t event_size,
                                                 void* user_data);

/**
 * @brief Register a proto-byte stream callback on an STT component handle.
 *
 * One registration per handle. Calling again replaces the previous slot.
 * Pass NULL to clear.
 *
 * @retval RAC_SUCCESS                     Callback registered.
 * @retval RAC_ERROR_INVALID_HANDLE        @p handle is null or invalid.
 * @retval RAC_ERROR_SERVICE_BUSY          Component lifecycle teardown is in progress.
 *
 * @warning user_data ownership and lifetime (cross-SDK
 *          contract — see rac_llm_stream.h for the canonical recipe). The C
 *          runtime may invoke `callback(bytes, size, user_data)` on a
 *          background thread AFTER rac_stt_unset_stream_proto_callback(handle)
 *          has returned, because the dispatcher copies the callback slot
 *          under its internal mutex and releases the mutex BEFORE invoking
 *          the user callback (see rac_stt_stream.cpp
 *          lock-release-before-callback comment). The caller MUST ensure no
 *          in-flight invocation is executing on a background thread before
 *          freeing @p user_data.
 *
 *          Recommended teardown sequence:
 *            (a) call rac_stt_unset_stream_proto_callback(handle) — clears
 *                the slot atomically so no NEW dispatches will fire;
 *            (b) call rac_stt_proto_quiesce() — spin-waits until every
 *                in-flight callback invocation has returned;
 *            (c) free @p user_data.
 *
 *          Modalities that currently expose proto_quiesce: LLM
 *          (rac_llm_stream.h), STT (this header), TTS (rac_tts_stream.h),
 *          VAD (rac_vad_stream.h), Diffusion (rac_diffusion_stream.h), VLM
 *          (rac_vlm_service.h). voice_agent quiesces in-flight callbacks as
 *          part of rac_voice_agent_destroy() rather than exposing a
 *          standalone quiesce entry point. SDK fan-out helpers
 *          (Swift HandleStreamAdapter, Kotlin/Flutter/RN equivalents)
 *          centralize this dance for their host language; refer to the
 *          canonical adapter implementation when porting a new SDK.
 */
RAC_API rac_result_t rac_stt_set_stream_proto_callback(rac_handle_t handle,
                                                       rac_stt_stream_proto_callback_fn callback,
                                                       void* user_data);

/**
 * @brief Unregister the proto-byte stream callback for a handle.
 *
 * Equivalent to `rac_stt_set_stream_proto_callback(handle, NULL, NULL)`.
 */
RAC_API rac_result_t rac_stt_unset_stream_proto_callback(rac_handle_t handle);

/**
 * @brief Spin-wait until all in-flight STT proto-byte stream dispatches have
 *        returned. Mirrors rac_vlm_proto_quiesce / rac_llm_proto_quiesce.
 *        Callers freeing user_data passed into
 *        rac_stt_set_stream_proto_callback, or tearing down the STT
 *        component, should call this after the unset before freeing the
 *        user_data. Safe to call from any thread, including re-entrantly from
 *        a callback. A re-entrant call waits for every dispatch on other
 *        threads but necessarily returns before callback frames already active
 *        on the calling thread have unwound; user_data must remain alive until
 *        those frames return.
 */
RAC_API void rac_stt_proto_quiesce(void);

/**
 * @brief Start a streaming transcription session.
 *
 * Parses @p options_proto_bytes as a serialized `runanywhere.v1.STTOptions`
 * and creates a session bound to @p handle. The lifecycle manager tracks
 * the session — unloading the model cancels it automatically.
 *
 * @param handle              STT component handle.
 * @param options_proto_bytes Serialized `runanywhere.v1.STTOptions` (may be empty).
 * @param options_proto_size  Number of bytes at @p options_proto_bytes.
 * @param out_session_id      Output: opaque non-zero session id on success.
 *
 * @retval RAC_SUCCESS                     Session started.
 * @retval RAC_ERROR_INVALID_HANDLE        @p handle is null or invalid.
 * @retval RAC_ERROR_NULL_POINTER          @p out_session_id is null.
 * @retval RAC_ERROR_SERVICE_BUSY          Component model lifecycle teardown is in progress.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE Library was built without Protobuf.
 * @retval RAC_ERROR_NOT_IMPLEMENTED       Session backend not yet wired (stub).
 */
RAC_API rac_result_t rac_stt_stream_start_proto(rac_handle_t handle,
                                                const uint8_t* options_proto_bytes,
                                                size_t options_proto_size,
                                                uint64_t* out_session_id);

/**
 * @brief Feed an audio frame into a streaming STT session.
 *
 * The session id MUST come from a successful `rac_stt_stream_start_proto()`
 * call on the same handle. Each accepted frame may produce zero or more
 * STTStreamEvent proto bytes via the registered stream callback.
 *
 * @param session_id    Session id returned by rac_stt_stream_start_proto().
 * @param audio_bytes   PCM audio bytes (encoding per the session options).
 * @param audio_size    Number of bytes at @p audio_bytes.
 *
 * @retval RAC_SUCCESS                Frame accepted.
 * @retval RAC_ERROR_INVALID_ARGUMENT Session id unknown or audio buffer null.
 * @retval RAC_ERROR_NOT_IMPLEMENTED  Session backend not yet wired (stub).
 */
RAC_API rac_result_t rac_stt_stream_feed_audio_proto(uint64_t session_id,
                                                     const uint8_t* audio_bytes, size_t audio_size);

/**
 * @brief Stop a streaming STT session, flushing any pending final events.
 *
 * After this call returns, no further events will be delivered for the
 * session and the id becomes invalid.
 */
RAC_API rac_result_t rac_stt_stream_stop_proto(uint64_t session_id);

/**
 * @brief Cancel a streaming STT session and drain accepted provider work.
 *
 * Cancellation closes the session's dispatch gate immediately, so no new
 * events are admitted and pending buffered audio is dropped. It does not
 * interrupt a provider call that is already executing. If a feed or callback
 * is in flight, this call waits for it to return before destroying the backend
 * stream handle. When called outside the session's callback, no callback for
 * the session is running after this function returns. If cancellation is
 * requested re-entrantly from that session's own callback, it cannot wait for
 * itself; cleanup is deferred until the callback and provider feed unwind.
 * Both paths suppress all later events.
 */
RAC_API rac_result_t rac_stt_stream_cancel_proto(uint64_t session_id);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_STT_RAC_STT_STREAM_H */
