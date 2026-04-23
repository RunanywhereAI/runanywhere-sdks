/**
 * @file rac_voice_event_abi.h
 * @brief Proto-encoded VoiceEvent callback ABI for the voice agent.
 *
 * GAP 09 Phase 15 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
 *
 * This is the second event-delivery path on the voice agent, alongside the
 * existing struct callback (`rac_voice_agent_event_callback_fn` declared in
 * `rac_voice_agent.h`). Frontends that consume the IDL-generated
 * `runanywhere.v1.VoiceEvent` proto type subscribe through here; frontends
 * that already speak the C struct stay on the legacy path.
 *
 * Why a second path:
 *   - The struct path emits one of several union arms. Per-language
 *     mappings hand-write a switch to translate the union into the
 *     idiomatic event type (~90 LOC × 5 languages today).
 *   - The proto path emits one consistent serialized payload. Per-language
 *     adapter is ~60 LOC of "deserialize bytes → AsyncStream<VoiceEvent>"
 *     using the codegen'd type. Saves ~150 LOC per SDK.
 *
 * Stability:
 *   - This header is GAP 09 NEW. The struct path is unchanged. Both
 *     callbacks may be set on the same handle; both fire per event. No
 *     contention with the GAP 02 plugin ABI version.
 *   - RAC_ABI_VERSION (declared below) bumped to 2 by this header so
 *     consumers can detect runtime support.
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
 * @brief RAC C ABI version. Bumped from 1 to 2 by GAP 09 to advertise the
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
                                                         size_t         event_size,
                                                         void*          user_data);

/**
 * @brief Register a proto-byte event callback on a voice agent handle.
 *
 * Coexists with the struct callback registered via the existing
 * `rac_voice_agent_set_event_callback()` API. Both fire on every event.
 *
 * @param handle     Voice agent handle obtained from rac_voice_agent_create().
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
RAC_API rac_result_t rac_voice_agent_set_proto_callback(rac_voice_agent_handle_t                  handle,
                                                        rac_voice_agent_proto_event_callback_fn   callback,
                                                        void*                                     user_data);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H */
