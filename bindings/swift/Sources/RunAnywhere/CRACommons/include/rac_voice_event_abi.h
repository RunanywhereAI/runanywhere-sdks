/**
 * @file rac_voice_event_abi.h
 * @brief Proto-encoded VoiceEvent callback ABI for the voice agent.
 *
 * The voice agent delivers events as one serialized
 * `runanywhere.v1.VoiceEvent` payload. SDK adapters deserialize those bytes
 * into their generated event type.
 *
 * Stability:
 *   - This callback and `rac_voice_agent_process_turn_proto` carry the same
 *     VoiceEvent wire format. No contention with the plugin ABI version.
 *   - RAC_ABI_VERSION is 2 so consumers can detect runtime support.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H
#define RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_voice_agent.h"

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
                                                         size_t         event_size,
                                                         void*          user_data);

/**
 * @brief Register a proto-byte event callback on a voice agent handle.
 *
 * The registered callback fires once per VoiceEvent emitted by the agent.
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
RAC_API rac_result_t rac_voice_agent_set_proto_callback(rac_voice_agent_handle_t                  handle,
                                                        rac_voice_agent_proto_event_callback_fn   callback,
                                                        void*                                     user_data);

/**
 * @brief Spin-wait until all in-flight voice-agent proto-byte dispatches
 *        return.
 *
 * Call after clearing the callback and before freeing its user_data. Safe to
 * call from any thread.
 */
RAC_API void rac_voice_agent_proto_quiesce(void);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_H */
