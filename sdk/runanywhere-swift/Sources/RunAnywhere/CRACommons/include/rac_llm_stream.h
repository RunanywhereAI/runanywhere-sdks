/**
 * @file rac_llm_stream.h
 * @brief Proto-encoded LLMStreamEvent callback ABI for LLM token streaming.
 *
 * v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
 *
 * Unified replacement for the per-SDK hand-rolled LLM streaming shims
 * (Swift AsyncThrowingStream, Kotlin callbackFlow, Dart StreamController,
 * RN tokenQueue, Web HEAPU8 copy). Mirrors the proto-byte voice agent
 * ABI declared in `rac_voice_event_abi.h` — one registration per handle,
 * N collectors via language-level fan-out, bytes serialized from
 * `runanywhere.v1.LLMStreamEvent`.
 *
 * Usage (C):
 *     rac_handle_t llm = ...;
 *     rac_llm_set_stream_proto_callback(llm, my_cb, my_ud);
 *     // each rac_llm_component_generate_stream() emits one
 *     // LLMStreamEvent per token, serialized to bytes, delivered via my_cb.
 *     rac_llm_unset_stream_proto_callback(llm);
 *
 * Lifetime: the buffer passed to the callback is valid only for the
 * duration of the callback invocation. Callers that retain bytes MUST
 * copy them out — the C++ side reuses a thread-local scratch buffer and
 * an arena-backed proto message (`cc_enable_arenas` in llm_service.proto)
 * across events, so holding onto the pointer is undefined behavior.
 */

#ifndef RAC_FEATURES_LLM_RAC_LLM_STREAM_H
#define RAC_FEATURES_LLM_RAC_LLM_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Callback fired once per LLMStreamEvent with serialized proto bytes.
 *
 * @param event_bytes Pointer to `runanywhere.v1.LLMStreamEvent.SerializeToArray(...)` output.
 * @param event_size  Number of valid bytes at @p event_bytes.
 * @param user_data   Opaque pointer registered with
 *                    rac_llm_set_stream_proto_callback().
 *
 * See file header for lifetime constraints on @p event_bytes.
 */
typedef void (*rac_llm_stream_proto_callback_fn)(const uint8_t* event_bytes,
                                                  size_t         event_size,
                                                  void*          user_data);

/**
 * @brief Register a proto-byte stream callback on an LLM component handle.
 *
 * Coexists with the struct-callback path exposed by
 * `rac_llm_component_generate_stream()` — both fire on every token. The
 * proto path is the idiomatic one for frontend adapters; the struct path
 * remains available for C-only callers that cannot link Protobuf.
 *
 * @param handle     LLM component handle from rac_llm_component_create().
 * @param callback   Proto-byte stream callback. Pass NULL to clear.
 * @param user_data  Opaque pointer passed back on every invocation.
 *
 * @retval RAC_SUCCESS                     Callback registered.
 * @retval RAC_ERROR_INVALID_HANDLE        @p handle is null or invalid.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE The library was built without
 *                                         Protobuf (no rac_idl target);
 *                                         frontend should fall back to
 *                                         the struct callback path.
 */
RAC_API rac_result_t rac_llm_set_stream_proto_callback(rac_handle_t                    handle,
                                                        rac_llm_stream_proto_callback_fn callback,
                                                        void*                           user_data);

/**
 * @brief Unregister the proto-byte stream callback for a handle.
 *
 * Equivalent to calling `rac_llm_set_stream_proto_callback(handle, NULL, NULL)`.
 *
 * @param handle LLM component handle.
 * @retval RAC_SUCCESS              Registration cleared (or was already empty).
 * @retval RAC_ERROR_INVALID_HANDLE @p handle is null.
 */
RAC_API rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* RAC_FEATURES_LLM_RAC_LLM_STREAM_H */
