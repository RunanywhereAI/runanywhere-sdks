/**
 * @file rac_voice_event_abi.cpp
 * @brief Implementation of the GAP 09 proto-byte event ABI for the voice
 *        agent. See rac_voice_event_abi.h for the declared contract.
 *
 * Implementation notes:
 *   - When the build was configured with Protobuf available, the rac_idl
 *     target ships `voice_events.pb.h` and we serialize each emitted
 *     `rac_voice_agent_event_t` into `runanywhere::v1::VoiceEvent` via
 *     `SerializeToArray()`, calling the registered callback with the bytes.
 *   - When the build was configured without Protobuf, the function returns
 *     `RAC_ERROR_FEATURE_NOT_AVAILABLE` and the frontend falls back to the
 *     struct callback path.
 *
 * The actual hookup of `rac_voice_agent_set_proto_callback()` into the
 * agent's internal event dispatcher lives in the agent's source file
 * (under engines/voice_agent_orchestrator/ or similar) — we provide the
 * registration storage + a helper that the dispatcher calls per event.
 *
 * Today this file only provides the C ABI surface (registration/storage
 * + capability check). The dispatcher integration is queued for the
 * companion commit that wires it into voice_agent.cpp's event loop.
 */

#include "rac/features/voice_agent/rac_voice_event_abi.h"

#include "rac/core/rac_logger.h"

#include <atomic>
#include <mutex>
#include <unordered_map>

namespace {

/** Registered (callback, user_data) per handle. NULL callback = unregistered. */
struct CallbackSlot {
    rac_voice_agent_proto_event_callback_fn fn       = nullptr;
    void*                                   user_data = nullptr;
};

std::mutex&                                              g_mu()    { static std::mutex m; return m; }
std::unordered_map<rac_voice_agent_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_voice_agent_handle_t, CallbackSlot> m;
    return m;
}

}  // namespace

extern "C" {

rac_result_t rac_voice_agent_set_proto_callback(rac_voice_agent_handle_t                handle,
                                                 rac_voice_agent_proto_event_callback_fn callback,
                                                 void*                                   user_data) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }

#ifndef RAC_HAVE_PROTOBUF
    /* Build without Protobuf. The slot will be tracked but the dispatcher
     * never has anything to serialize, so the callback fires zero times.
     * Returning FEATURE_NOT_AVAILABLE lets the frontend pick the struct
     * callback path immediately. */
    (void)callback;
    (void)user_data;
    RAC_LOG_WARNING("voice_agent",
                    "rac_voice_agent_set_proto_callback: Protobuf not compiled in "
                    "(RAC_HAVE_PROTOBUF undefined). Falling back to struct callback.");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = CallbackSlot{ callback, user_data };
    }
    return RAC_SUCCESS;
#endif
}

}  // extern "C"

#ifdef RAC_HAVE_PROTOBUF
namespace rac::voice_agent {

/**
 * @brief Internal helper called by the voice agent's event dispatcher per
 *        emitted event. Translates the C event struct into a serialized
 *        runanywhere.v1.VoiceEvent and invokes the registered callback.
 *
 * This symbol is NOT in the public C ABI — it's C++-only and used by
 * voice_agent.cpp's dispatcher to fan out one event into both the struct
 * callback (existing) and the proto-byte callback (new).
 *
 * Stub today (returns immediately). The companion commit that wires it
 * into voice_agent.cpp will fill in the SerializeToArray + dispatch.
 */
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                           const rac_voice_agent_event_t* /*event*/) {
    CallbackSlot slot;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
    }

    /* TODO Phase 16-19 follow-up: build the runanywhere::v1::VoiceEvent,
     * SerializeToArray into a thread-local buffer, then call
     *     slot.fn(buf.data(), buf.size(), slot.user_data);
     * The arena (cc_enable_arenas in voice_events.proto) is reused across
     * dispatches via a thread_local arena pool. */
}

}  // namespace rac::voice_agent
#endif  /* RAC_HAVE_PROTOBUF */
