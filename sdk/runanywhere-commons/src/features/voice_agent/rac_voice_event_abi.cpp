/**
 * @file rac_voice_event_abi.cpp
 * @brief Implementation of the proto-byte event ABI for the voice
 *        agent. See rac_voice_event_abi.h for the declared contract.
 *
 * The callback registry (`rac_voice_agent_set_proto_callback` /
 * `rac_voice_agent_proto_quiesce`) is platform-agnostic; only the per-event
 * dispatch (`dispatch_proto_voice_event`) depends on libprotobuf. When the
 * library is built without Protobuf (no `RAC_HAVE_PROTOBUF`, e.g. Android),
 * the generated `runanywhere::v1::VoiceEvent` type is unavailable so the
 * dispatcher compiles to a no-op; the d7 full-session ABI emits events through
 * its own hand-encoded path in that configuration.
 *
 * The hookup of `rac_voice_agent_set_proto_callback()` into the agent's event
 * dispatcher lives in voice_agent_d7_abi.cpp / voice_agent_internal_helpers.cpp
 * — they build a `VoiceEvent` and call dispatch_proto_voice_event() (declared
 * in rac_voice_event_abi_internal.h) per event.
 */

#include "rac/features/voice_agent/rac_voice_event_abi.h"

#include "rac_voice_event_abi_internal.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"

namespace {

/** Registered (callback, user_data) per handle. */
struct CallbackSlot {
    rac_voice_agent_proto_event_callback_fn fn = nullptr;
    void* user_data = nullptr;
    // Per-handle, per-session sequence counter. Mirrors the LLM stream fix:
    // a process-wide counter caused decoders to reject the
    // second session on the same handle. Reset on every fresh registration
    // so each session starts at 1 again.
    uint64_t seq = 0;
};

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}
std::unordered_map<rac_voice_agent_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_voice_agent_handle_t, CallbackSlot> m;
    return m;
}

// In-flight counter for the proto-byte event
// dispatcher. Mirrors the LLM/VLM/VAD stream quiesce pattern. Callers
// freeing user_data must (a) unregister via rac_voice_agent_set_proto_callback
// then (b) call rac_voice_agent_proto_quiesce to spin-wait until every
// concurrent dispatch_proto_voice_event invocation has returned before freeing
// user_data. Without (b), a thread that copied the slot before (a) ran can
// still be inside slot.fn() with a stale user_data pointer.
std::atomic<int>& proto_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

struct ProtoInFlightGuard {
    ProtoInFlightGuard() { proto_in_flight().fetch_add(1, std::memory_order_acq_rel); }
    ~ProtoInFlightGuard() { proto_in_flight().fetch_sub(1, std::memory_order_acq_rel); }
    ProtoInFlightGuard(const ProtoInFlightGuard&) = delete;
    ProtoInFlightGuard& operator=(const ProtoInFlightGuard&) = delete;
};

}  // namespace

extern "C" {

rac_result_t rac_voice_agent_set_proto_callback(rac_voice_agent_handle_t handle,
                                                rac_voice_agent_proto_event_callback_fn callback,
                                                void* user_data) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        // Always start with seq = 0 for a fresh session.
        g_slots()[handle] = CallbackSlot{.fn = callback, .user_data = user_data, .seq = 0};
    }
    return RAC_SUCCESS;
}

void rac_voice_agent_proto_quiesce(void) {
    while (proto_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
}

}  // extern "C"

#ifdef RAC_HAVE_PROTOBUF

#include "voice_events.pb.h"

namespace {

int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

}  // namespace

namespace rac::voice_agent {

/**
 * @brief Fan a generated VoiceEvent out to the proto-byte callback registered
 *        for @p handle. Fills seq/timestamp when the caller left them at proto
 *        defaults, serializes, and invokes the registered callback.
 *
 * Threading:
 *   - The (callback, user_data) pair is captured under the registry mutex
 *     so we do not hold the lock across the user callback (avoids deadlock
 *     if the callback re-enters rac_voice_agent_set_proto_callback).
 *   - The serialization buffer is thread_local so concurrent dispatches on
 *     different threads do not contend on heap allocation. The arena reuse
 *     comes for free from `cc_enable_arenas` in voice_events.proto.
 */
void dispatch_proto_voice_event(rac_voice_agent_handle_t handle,
                                const runanywhere::v1::VoiceEvent& event) {
    // Hold the in-flight guard across the whole
    // dispatch so rac_voice_agent_proto_quiesce() can spin-wait on the
    // counter before user_data is freed by a concurrent teardown thread.
    ProtoInFlightGuard in_flight_guard;
    CallbackSlot slot;
    uint64_t seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        slot = it->second;
        // Bump the per-handle counter under the lock so concurrent dispatches
        // on the same handle still produce monotonic seq values.
        seq = ++(it->second.seq);
    }

    thread_local std::vector<uint8_t> scratch;

    runanywhere::v1::VoiceEvent proto_event(event);
    if (proto_event.seq() == 0) {
        proto_event.set_seq(seq);
    }
    if (proto_event.timestamp_us() == 0) {
        proto_event.set_timestamp_us(now_us());
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed)
        scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        /* Serialization should never fail for a valid message; log and
         * drop instead of crashing. */
        RAC_LOG_WARNING("voice_agent",
                        "dispatch_proto_voice_event: SerializeToArray failed for payload case=%d",
                        static_cast<int>(proto_event.payload_case()));
        return;
    }

    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::voice_agent

#else /* RAC_HAVE_PROTOBUF not defined */

namespace rac::voice_agent {

void dispatch_proto_voice_event(rac_voice_agent_handle_t, const runanywhere::v1::VoiceEvent&) {
    // Generated VoiceEvent dispatch is only available when libprotobuf is linked.
}

}  // namespace rac::voice_agent

#endif /* RAC_HAVE_PROTOBUF */
