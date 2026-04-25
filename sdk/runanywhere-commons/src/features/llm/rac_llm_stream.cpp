/**
 * @file rac_llm_stream.cpp
 * @brief Implementation of the v2 close-out Phase G-2 LLM proto-byte
 *        stream ABI. See rac_llm_stream.h for the declared contract.
 *
 * Implementation mirrors rac_voice_event_abi.cpp:
 *   - Registry maps (rac_handle_t -> CallbackSlot) protected by a mutex.
 *   - `dispatch_llm_stream_event()` is invoked by llm_component.cpp once
 *     per emitted token (and once for the terminal finish event) with
 *     the token text, is_final flag, token kind, and optional finish/
 *     error reason. It translates into a `runanywhere.v1.LLMStreamEvent`,
 *     serializes to a thread-local scratch buffer, and invokes the
 *     registered callback (without holding the registry lock).
 *   - When the library is built without Protobuf (no `RAC_HAVE_PROTOBUF`),
 *     registration returns RAC_ERROR_FEATURE_NOT_AVAILABLE and
 *     `dispatch_llm_stream_event` is a no-op — frontend adapters fall
 *     back to the struct-callback path.
 */

#include "rac/features/llm/rac_llm_stream.h"

#include "rac/core/rac_logger.h"

#include <atomic>
#include <mutex>
#include <unordered_map>

namespace {

struct CallbackSlot {
    rac_llm_stream_proto_callback_fn fn        = nullptr;
    void*                            user_data = nullptr;
};

std::mutex&                                 g_mu()    { static std::mutex m; return m; }
std::unordered_map<rac_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_handle_t, CallbackSlot> m;
    return m;
}

}  // namespace

extern "C" {

rac_result_t rac_llm_set_stream_proto_callback(rac_handle_t                    handle,
                                                rac_llm_stream_proto_callback_fn callback,
                                                void*                           user_data) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }

#ifndef RAC_HAVE_PROTOBUF
    (void)callback;
    (void)user_data;
    RAC_LOG_WARNING("llm",
                    "rac_llm_set_stream_proto_callback: Protobuf not compiled in "
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

rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
#ifdef RAC_HAVE_PROTOBUF
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
#endif
    return RAC_SUCCESS;
}

}  // extern "C"

#ifdef RAC_HAVE_PROTOBUF

#include "llm_service.pb.h"

#include <chrono>
#include <vector>

namespace {

/* Monotonic per-process sequence counter for LLMStreamEvent.seq. proto3
 * uint64 wraps on overflow; for any practical stream this will not happen. */
std::atomic<uint64_t> g_seq_counter{0};

int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

}  // namespace

namespace rac::llm {

/**
 * @brief Map a RAC_LLM_* token kind (internal / engine-specific) to the
 *        proto `LLMTokenKind`. Today llm_component.cpp emits only ANSWER
 *        tokens; THOUGHT / TOOL_CALL arms are reserved for the pending
 *        thinking-parser + tool-calling integration.
 */
runanywhere::v1::LLMTokenKind to_proto_kind(int internal_kind) {
    switch (internal_kind) {
        case 1: return runanywhere::v1::LLM_TOKEN_KIND_ANSWER;
        case 2: return runanywhere::v1::LLM_TOKEN_KIND_THOUGHT;
        case 3: return runanywhere::v1::LLM_TOKEN_KIND_TOOL_CALL;
        default: return runanywhere::v1::LLM_TOKEN_KIND_UNSPECIFIED;
    }
}

/**
 * @brief Internal helper invoked by llm_component.cpp's streaming
 *        dispatcher per token. Serializes one `LLMStreamEvent` and
 *        fires the registered callback.
 *
 * Thread safety: captures the (callback, user_data) pair under the
 * registry mutex but does NOT hold the lock across the user callback —
 * this avoids deadlock if the callback re-enters
 * rac_llm_set_stream_proto_callback() (e.g. a collector that
 * self-unsubscribes on final token).
 *
 * The proto message + serialization buffer are thread_local so
 * concurrent dispatches on different threads do not contend on heap
 * allocation. Arena reuse is automatic per `cc_enable_arenas` in
 * llm_service.proto.
 */
void dispatch_llm_stream_event(rac_handle_t handle,
                               const char*  token,
                               bool         is_final,
                               int          kind,
                               uint32_t     token_id,
                               float        logprob,
                               const char*  finish_reason,
                               const char*  error_message) {
    CallbackSlot slot;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
    }

    thread_local runanywhere::v1::LLMStreamEvent proto_event;
    thread_local std::vector<uint8_t>            scratch;

    proto_event.Clear();
    proto_event.set_seq(g_seq_counter.fetch_add(1, std::memory_order_relaxed) + 1);
    proto_event.set_timestamp_us(now_us());
    if (token) {
        proto_event.set_token(token);
    }
    proto_event.set_is_final(is_final);
    proto_event.set_kind(to_proto_kind(kind));
    if (token_id != 0) {
        proto_event.set_token_id(token_id);
    }
    if (logprob != 0.0f) {
        proto_event.set_logprob(logprob);
    }
    if (finish_reason && finish_reason[0] != '\0') {
        proto_event.set_finish_reason(finish_reason);
    }
    if (error_message && error_message[0] != '\0') {
        proto_event.set_error_message(error_message);
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed) scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("llm",
                        "dispatch_llm_stream_event: SerializeToArray failed "
                        "(is_final=%d)", is_final ? 1 : 0);
        return;
    }

    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::llm

#else /* RAC_HAVE_PROTOBUF not defined */

namespace rac::llm {
void dispatch_llm_stream_event(rac_handle_t /*handle*/,
                               const char*  /*token*/,
                               bool         /*is_final*/,
                               int          /*kind*/,
                               uint32_t     /*token_id*/,
                               float        /*logprob*/,
                               const char*  /*finish_reason*/,
                               const char*  /*error_message*/) {
    // No-op: registry never has entries when Protobuf is absent.
}
}  // namespace rac::llm

#endif /* RAC_HAVE_PROTOBUF */
