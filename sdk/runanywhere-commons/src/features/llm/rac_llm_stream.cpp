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
 *   - When the library is built without Protobuf (no `RAC_HAVE_PROTOBUF`,
 *     e.g. Android), the implementation hand-encodes LLMStreamEvent into
 *     protobuf wire format. The schema is small + stable so this avoids
 *     pulling 12 MB of libprotobuf into every Android APK just for one
 *     message. Layout matches `idl/llm_service.proto` field-for-field.
 */

#include "rac/features/llm/rac_llm_stream.h"

#include "rac/core/rac_logger.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

struct CallbackSlot {
    rac_llm_stream_proto_callback_fn fn        = nullptr;
    void*                            user_data = nullptr;
    // B-FL-7-001 fix: per-handle, per-session sequence counter. Previously a
    // single process-wide `g_seq_counter` was used, which kept growing across
    // generateStream calls; the Wire / protobuf-java decoder threw "end-group
    // tag did not match" the second time on the same handle, presumably because
    // some collector treated drift in `seq` values as a corrupted stream. Reset
    // seq on every fresh `set_stream_proto_callback` so each session starts at
    // 1 again.
    uint64_t seq = 0;
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

    // The registry path is identical with or without Protobuf — we only
    // diverge in how `dispatch_llm_stream_event` serializes the event.
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        // Always start with seq = 0 for a fresh session.
        g_slots()[handle] = CallbackSlot{ callback, user_data, /*seq=*/0 };
    }
    return RAC_SUCCESS;
}

rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

}  // extern "C"

#ifdef RAC_HAVE_PROTOBUF

#include "llm_service.pb.h"

#include <chrono>
#include <vector>

namespace {

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
    uint64_t seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        seq = ++(it->second.seq);
    }

    thread_local runanywhere::v1::LLMStreamEvent proto_event;
    thread_local std::vector<uint8_t>            scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
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

// =============================================================================
// Hand-encoded protobuf wire format for runanywhere.v1.LLMStreamEvent.
//
// We avoid linking libprotobuf on Android (saves ~12 MB per app, and the
// NDK does not ship Protobuf out of the box) by serializing this single
// message manually. Wire format reference:
//   https://protobuf.dev/programming-guides/encoding/
//
// Field numbers and types must match `idl/llm_service.proto`:
//   1: uint64 seq            (varint)
//   2: int64  timestamp_us   (varint)
//   3: string token          (length-delimited)
//   4: bool   is_final       (varint)
//   5: enum   kind           (varint)
//   6: uint32 token_id       (varint)
//   7: float  logprob        (fixed32)
//   8: string finish_reason  (length-delimited)
//   9: string error_message  (length-delimited)
//
// proto3 default-value omission semantics are preserved: scalars equal to
// their type's default (0, false, empty string) are skipped on the wire.
// =============================================================================

namespace {

int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

inline void wire_varint(std::vector<uint8_t>& out, uint64_t value) {
    while (value >= 0x80u) {
        out.push_back(static_cast<uint8_t>(value | 0x80u));
        value >>= 7;
    }
    out.push_back(static_cast<uint8_t>(value));
}

inline void wire_tag(std::vector<uint8_t>& out, uint32_t field, uint32_t wire_type) {
    wire_varint(out, (static_cast<uint64_t>(field) << 3) | wire_type);
}

inline void wire_uint64_field(std::vector<uint8_t>& out, uint32_t field, uint64_t value) {
    if (value == 0) return;  // proto3 default omission
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, value);
}

inline void wire_int64_field(std::vector<uint8_t>& out, uint32_t field, int64_t value) {
    if (value == 0) return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, static_cast<uint64_t>(value));  // varint, not zigzag (proto3 int64)
}

inline void wire_uint32_field(std::vector<uint8_t>& out, uint32_t field, uint32_t value) {
    if (value == 0) return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, value);
}

inline void wire_bool_field(std::vector<uint8_t>& out, uint32_t field, bool value) {
    if (!value) return;
    wire_tag(out, field, /*wire_type=*/0);
    out.push_back(0x01);
}

inline void wire_enum_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0) return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, static_cast<uint64_t>(value));
}

inline void wire_float_field(std::vector<uint8_t>& out, uint32_t field, float value) {
    if (value == 0.0f) return;
    wire_tag(out, field, /*wire_type=*/5);
    uint32_t bits;
    std::memcpy(&bits, &value, sizeof(bits));  // bit-cast (memcpy avoids strict-aliasing UB)
    out.push_back(static_cast<uint8_t>(bits & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 8) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 16) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 24) & 0xff));
}

inline void wire_string_field(std::vector<uint8_t>& out, uint32_t field, const char* str) {
    if (str == nullptr || str[0] == '\0') return;
    const size_t len = std::strlen(str);
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, len);
    out.insert(out.end(), str, str + len);
}

int32_t to_proto_kind(int internal_kind) {
    switch (internal_kind) {
        case 1: return 1;  // ANSWER
        case 2: return 2;  // THOUGHT
        case 3: return 3;  // TOOL_CALL
        default: return 0;  // UNSPECIFIED
    }
}

}  // namespace

namespace rac::llm {
void dispatch_llm_stream_event(rac_handle_t handle,
                               const char*  token,
                               bool         is_final,
                               int          kind,
                               uint32_t     token_id,
                               float        logprob,
                               const char*  finish_reason,
                               const char*  error_message) {
    CallbackSlot slot;
    uint64_t seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        // Bump the per-handle counter under the lock so concurrent dispatches
        // on the same handle still produce monotonic seq values.
        seq = ++(it->second.seq);
    }

    thread_local std::vector<uint8_t> scratch;
    scratch.clear();
    scratch.reserve(64);

    wire_uint64_field(scratch, 1, seq);
    wire_int64_field (scratch, 2, now_us());
    wire_string_field(scratch, 3, token);
    wire_bool_field  (scratch, 4, is_final);
    wire_enum_field  (scratch, 5, to_proto_kind(kind));
    wire_uint32_field(scratch, 6, token_id);
    wire_float_field (scratch, 7, logprob);
    wire_string_field(scratch, 8, finish_reason);
    wire_string_field(scratch, 9, error_message);

    slot.fn(scratch.data(), scratch.size(), slot.user_data);
}
}  // namespace rac::llm

#endif /* RAC_HAVE_PROTOBUF */
