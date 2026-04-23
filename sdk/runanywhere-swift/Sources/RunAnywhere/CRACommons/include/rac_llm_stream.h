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
 * Flat-header copy for the Swift SDK's CRACommons module — the canonical
 * source is `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_stream.h`.
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

typedef void (*rac_llm_stream_proto_callback_fn)(const uint8_t* event_bytes,
                                                  size_t         event_size,
                                                  void*          user_data);

rac_result_t rac_llm_set_stream_proto_callback(rac_handle_t                    handle,
                                                rac_llm_stream_proto_callback_fn callback,
                                                void*                           user_data);

rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* RAC_FEATURES_LLM_RAC_LLM_STREAM_H */
