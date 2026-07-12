/**
 * @file rac_voice_event_abi.h
 * @brief Proto-encoded VoiceEvent callback ABI for the voice agent.
 *
 * The voice agent delivers events as one consistent serialized
 * `runanywhere.v1.VoiceEvent` payload. Each SDK's adapter is ~60 LOC of
 * "deserialize bytes → AsyncStream<VoiceEvent>" using the codegen'd type — no
 * hand-written union-arm switch per language.
 *
 * Stability:
 *   - This proto-byte callback and the d7 per-turn event callback
 *     (`rac_voice_agent_process_turn_proto`) carry the same VoiceEvent wire
 *     format. No contention with the plugin ABI version.
 *   - RAC_ABI_VERSION (declared below) is 2 so consumers can detect runtime
 *     support.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `SDK-facing default`.
 * rac_voice_agent_set_proto_callback and the
 * rac_voice_agent_proto_event_callback_fn typedef carry serialized
 * runanywhere.v1.VoiceEvent bytes.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H
#define RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/features/voice_agent/rac_voice_agent.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief RAC C ABI version. Bumped from 1 to 2 to advertise the
 *        proto-byte event ABI. Distinct from `RAC_PLUGIN_API_VERSION` which
 *        gates the engine plugin vtable layout.
 */
#ifndef RAC_ABI_VERSION
#define RAC_ABI_VERSION 2u
#endif

/**
 * @brief Callback fired once per VoiceEvent with serialized proto bytes.
 *
 * @param event_bytes  Pointer to a buffer containing
 *                     `runanywhere.v1.VoiceEvent.SerializeToArray(...)` output.
 * @param event_size   Number of valid bytes at @p event_bytes.
 * @param user_data    Opaque pointer registered with
 *                     rac_voice_agent_set_proto_callback().
 *
 * Lifetime: the buffer is valid only for the duration of the callback. The
 * callback MUST copy bytes it intends to retain. The C++ side reuses an
 * internal arena across events (`cc_enable_arenas` on the proto), so
 * holding onto the pointer is undefined behavior.
 */
typedef void (*rac_voice_agent_proto_event_callback_fn)(const uint8_t* event_bytes,
                                                        size_t event_size, void* user_data);

/**
 * @brief Register a proto-byte event callback on a voice agent handle.
 *
 * The registered callback fires once per VoiceEvent emitted by the agent's
 * streaming / per-turn paths.
 *
 * @param handle     Voice agent handle obtained from rac_voice_agent_create_standalone().
 * @param callback   Proto-byte event callback function. Pass NULL to clear.
 * @param user_data  Opaque pointer passed back on every invocation.
 *
 * @retval RAC_SUCCESS                       Callback registered.
 * @retval RAC_ERROR_INVALID_HANDLE          @p handle is null or invalid.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE   The library was built without
 *                                           Protobuf — no rac_idl target,
 *                                           no proto-byte path. Frontend
 *                                           should fall back to the struct
 *                                           callback.
 */
RAC_API rac_result_t rac_voice_agent_set_proto_callback(
    rac_voice_agent_handle_t handle, rac_voice_agent_proto_event_callback_fn callback,
    void* user_data);

/**
 * @brief Spin-wait until every in-flight voice-agent proto-byte event
 *        dispatch has returned.
 *
 * Mirrors `rac_llm_proto_quiesce` / `rac_vlm_proto_quiesce` / `rac_vad_proto_quiesce`.
 * Callers freeing the `user_data` passed into
 * `rac_voice_agent_set_proto_callback`, or tearing down the voice agent
 * altogether, MUST follow the sequence:
 *
 *   (a) `rac_voice_agent_set_proto_callback(handle, NULL, NULL)` — clears
 *       the slot atomically so no NEW dispatches will fire;
 *   (b) `rac_voice_agent_proto_quiesce()` — spin-waits until every in-flight
 *       slot.fn() invocation has returned;
 *   (c) free @p user_data.
 *
 * Without (b), a concurrent `dispatch_proto_voice_event` thread that copied
 * the slot before (a) ran can still be inside `slot.fn()` with a stale
 * `user_data` pointer when the caller frees it.
 *
 * Safe to call from any thread; non-blocking when no dispatch is active.
 */
RAC_API void rac_voice_agent_proto_quiesce(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H */
