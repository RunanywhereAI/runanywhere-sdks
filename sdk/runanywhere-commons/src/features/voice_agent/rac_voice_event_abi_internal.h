/**
 * @file rac_voice_event_abi_internal.h
 * @brief Internal C++ entry point for the GAP 09 proto-byte event ABI.
 *
 * v2 close-out Phase 2 — paired with rac_voice_event_abi.cpp. NOT part of
 * the public C ABI; do NOT include from headers under include/. Only
 * voice_agent.cpp's event dispatcher calls this.
 */

#ifndef RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_INTERNAL_H
#define RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_INTERNAL_H

#include "rac/features/voice_agent/rac_voice_agent.h"

namespace rac::voice_agent {

/**
 * Fan one struct event out to the proto-byte callback registered for
 * @p handle (if any). No-op when no callback is registered or when the
 * build was configured without Protobuf.
 *
 * Safe to call from any thread that the voice agent's event dispatcher
 * runs on. Internal serialization buffers are thread_local.
 */
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                          const rac_voice_agent_event_t* event);

}  // namespace rac::voice_agent

#endif  /* RAC_FEATURES_VOICE_AGENT_RAC_VOICE_EVENT_ABI_INTERNAL_H */
