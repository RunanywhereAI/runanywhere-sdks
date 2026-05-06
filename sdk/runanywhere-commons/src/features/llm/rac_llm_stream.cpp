/**
 * @file rac_llm_stream.cpp
 * @brief Implementation of the v2 close-out Phase G-2 LLM proto-byte
 *        stream ABI. See rac_llm_stream.h for the declared contract.
 *
 * Implementation mirrors rac_voice_event_abi.cpp:
 *   - Registry maps (rac_handle_t -> CallbackSlot) protected by a mutex.
 *   - `dispatch_llm_stream_event()` is invoked by llm_component.cpp once
 *     per emitted token (and once for the terminal finish event). The
 *     struct overload (`LLMStreamEventParams`) is also invoked by
 *     `rac_llm_proto_service.cpp` via the shared
 *     `serialize_llm_stream_event()` helper — both call sites now use
 *     the same 13-field canonical emitter (BUG-STREAMING-001 fix).
 *   - When the library is built without Protobuf (no `RAC_HAVE_PROTOBUF`,
 *     e.g. Android legacy path), the implementation hand-encodes
 *     LLMStreamEvent into protobuf wire format. The schema is small +
 *     stable so this avoids pulling 12 MB of libprotobuf into every
 *     Android APK just for one message. Layout matches
 *     `idl/llm_service.proto` field-for-field.
 */

#include "rac/features/llm/rac_llm_stream.h"

#include "rac/core/rac_logger.h"
#include "features/llm/rac_llm_stream_internal.h"

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

int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
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
    // diverge in how `serialize_llm_stream_event` encodes the event.
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

namespace rac::llm {

int derive_event_kind(int kind, bool is_final, const char* error_message) {
    // Values match `runanywhere.v1.LLMStreamEventKind` in
    // idl/llm_service.proto. Encoded as int to keep this symbol
    // available on the hand-encoded (no-protobuf) WASM path.
    constexpr int kUnspecified = 0;
    constexpr int kToken       = 2;
    constexpr int kThinking    = 3;
    constexpr int kCompleted   = 6;
    constexpr int kError       = 7;
    constexpr int kTokenKindThought = 2;  // TOKEN_KIND_THOUGHT

    if (is_final) {
        return (error_message && error_message[0] != '\0') ? kError : kCompleted;
    }
    if (kind == kTokenKindThought) {
        return kThinking;
    }
    if (kind == 0) {
        return kUnspecified;
    }
    return kToken;
}

}  // namespace rac::llm

// =============================================================================
// Protobuf-backed serializer + dispatcher (desktop / iOS / Kotlin).
// =============================================================================

#ifdef RAC_HAVE_PROTOBUF

#include "llm_service.pb.h"

namespace rac::llm {

/**
 * @brief Map a RAC_LLM_* token kind (internal / engine-specific) to the
 *        canonical proto `TokenKind` (voice_events.proto). Today
 *        llm_component.cpp emits only ANSWER tokens; THOUGHT / TOOL_CALL
 *        arms are reserved for the pending thinking-parser +
 *        tool-calling integration.
 */
static runanywhere::v1::TokenKind to_proto_kind(int internal_kind) {
    switch (internal_kind) {
        case 1: return runanywhere::v1::TOKEN_KIND_ANSWER;
        case 2: return runanywhere::v1::TOKEN_KIND_THOUGHT;
        case 3: return runanywhere::v1::TOKEN_KIND_TOOL_CALL;
        default: return runanywhere::v1::TOKEN_KIND_UNSPECIFIED;
    }
}

bool serialize_llm_stream_event(uint64_t                    seq,
                                const LLMStreamEventParams& p,
                                std::vector<uint8_t>&       out) {
    thread_local runanywhere::v1::LLMStreamEvent proto_event;
    proto_event.Clear();

    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    if (p.token) {
        proto_event.set_token(p.token);
    }
    proto_event.set_is_final(p.is_final);
    proto_event.set_kind(to_proto_kind(p.kind));
    if (p.token_id != 0) {
        proto_event.set_token_id(p.token_id);
    }
    if (p.logprob != 0.0f) {
        proto_event.set_logprob(p.logprob);
    }
    if (p.finish_reason && p.finish_reason[0] != '\0') {
        proto_event.set_finish_reason(p.finish_reason);
    }
    if (p.error_message && p.error_message[0] != '\0') {
        proto_event.set_error_message(p.error_message);
    }

    // Extended fields (BUG-STREAMING-001 unification). proto3 scalar
    // defaults mean callers that don't set these still emit identical
    // wire bytes to the pre-unification 9-field shape.
    const int event_kind = derive_event_kind(p.kind, p.is_final, p.error_message);
    if (event_kind != 0) {
        proto_event.set_event_kind(
            static_cast<runanywhere::v1::LLMStreamEventKind>(event_kind));
    }
    if (p.request_id && p.request_id[0] != '\0') {
        proto_event.set_request_id(p.request_id);
    }
    if (p.conversation_id && p.conversation_id[0] != '\0') {
        proto_event.set_conversation_id(p.conversation_id);
    }
    if (p.prompt_tokens_processed > 0) {
        proto_event.set_prompt_tokens_processed(p.prompt_tokens_processed);
    }
    if (p.completion_tokens_generated > 0) {
        proto_event.set_completion_tokens_generated(p.completion_tokens_generated);
    }
    if (p.elapsed_ms > 0) {
        proto_event.set_elapsed_ms(p.elapsed_ms);
    }
    if (p.error_code != 0) {
        proto_event.set_error_code(p.error_code);
    }
    if (p.final_result != nullptr) {
        *proto_event.mutable_result() = *p.final_result;
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (out.size() < needed) out.resize(needed);
    else                     out.resize(needed);
    if (needed > 0 &&
        !proto_event.SerializeToArray(out.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("llm",
                        "serialize_llm_stream_event: SerializeToArray failed "
                        "(is_final=%d)", p.is_final ? 1 : 0);
        return false;
    }
    return true;
}

}  // namespace rac::llm

#else /* RAC_HAVE_PROTOBUF not defined */

// =============================================================================
// Hand-encoded protobuf wire format for runanywhere.v1.LLMStreamEvent.
//
// We avoid linking libprotobuf on Android legacy / WASM (saves ~12 MB
// per app, and the NDK does not ship Protobuf out of the box) by
// serializing this single message manually. Wire format reference:
//   https://protobuf.dev/programming-guides/encoding/
//
// Field numbers and types must match `idl/llm_service.proto`:
//   1: uint64 seq                         (varint)
//   2: int64  timestamp_us                (varint)
//   3: string token                       (length-delimited)
//   4: bool   is_final                    (varint)
//   5: enum   kind                        (varint)
//   6: uint32 token_id                    (varint)
//   7: float  logprob                     (fixed32)
//   8: string finish_reason               (length-delimited)
//   9: string error_message               (length-delimited)
//  11: int32  error_code                  (varint)
//  12: enum   event_kind                  (varint)
//  13: string request_id                  (length-delimited)
//  14: string conversation_id             (length-delimited)
//  15: int32  prompt_tokens_processed     (varint)
//  16: int32  completion_tokens_generated (varint)
//  17: int64  elapsed_ms                  (varint)
//
// Field 10 (nested LLMStreamFinalResult) is NOT emitted on the
// hand-encoded path because no caller sets LLMStreamEventParams::final_result
// without libprotobuf (proto_service, the only populator of `result`,
// runs only with RAC_HAVE_PROTOBUF defined).
//
// proto3 default-value omission semantics are preserved: scalars equal
// to their type's default (0, false, empty string) are skipped on the
// wire.
// =============================================================================

namespace {

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

inline void wire_int32_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0) return;
    wire_tag(out, field, /*wire_type=*/0);
    // proto3 int32 uses plain varint (negative values are 10-byte sign-extended;
    // our callers only emit >= 0 values for token counters).
    wire_varint(out, static_cast<uint64_t>(value));
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

int32_t to_proto_kind_int(int internal_kind) {
    switch (internal_kind) {
        case 1: return 1;  // ANSWER
        case 2: return 2;  // THOUGHT
        case 3: return 3;  // TOOL_CALL
        default: return 0;  // UNSPECIFIED
    }
}

}  // namespace

namespace rac::llm {

bool serialize_llm_stream_event(uint64_t                    seq,
                                const LLMStreamEventParams& p,
                                std::vector<uint8_t>&       out) {
    out.clear();
    out.reserve(96);

    wire_uint64_field(out, /*field=*/1,  seq);
    wire_int64_field (out, /*field=*/2,  now_us());
    wire_string_field(out, /*field=*/3,  p.token);
    wire_bool_field  (out, /*field=*/4,  p.is_final);
    wire_enum_field  (out, /*field=*/5,  to_proto_kind_int(p.kind));
    wire_uint32_field(out, /*field=*/6,  p.token_id);
    wire_float_field (out, /*field=*/7,  p.logprob);
    wire_string_field(out, /*field=*/8,  p.finish_reason);
    wire_string_field(out, /*field=*/9,  p.error_message);

    // Extended fields (BUG-STREAMING-001 fix). Nested `result` (field
    // 10) is intentionally not encoded on the hand-rolled path — no
    // caller sets `p.final_result` without libprotobuf.
    wire_int32_field (out, /*field=*/11, p.error_code);
    wire_enum_field  (out, /*field=*/12, derive_event_kind(p.kind, p.is_final, p.error_message));
    wire_string_field(out, /*field=*/13, p.request_id);
    wire_string_field(out, /*field=*/14, p.conversation_id);
    wire_int32_field (out, /*field=*/15, p.prompt_tokens_processed);
    wire_int32_field (out, /*field=*/16, p.completion_tokens_generated);
    wire_int64_field (out, /*field=*/17, p.elapsed_ms);

    return true;
}

}  // namespace rac::llm

#endif /* RAC_HAVE_PROTOBUF */

// =============================================================================
// Registry-backed dispatchers (shared by both build paths).
// =============================================================================

namespace rac::llm {

/**
 * @brief Canonical registry-backed dispatcher.
 *
 * Thread safety: captures the (callback, user_data) pair under the
 * registry mutex but does NOT hold the lock across the user callback —
 * this avoids deadlock if the callback re-enters
 * rac_llm_set_stream_proto_callback() (e.g. a collector that
 * self-unsubscribes on final token).
 *
 * The serialization buffer is thread_local so concurrent dispatches on
 * different threads do not contend on heap allocation.
 */
void dispatch_llm_stream_event(rac_handle_t                handle,
                               const LLMStreamEventParams& p) {
    CallbackSlot slot;
    uint64_t seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        // Bump the per-handle counter under the lock so concurrent
        // dispatches on the same handle still produce monotonic seq values.
        seq = ++(it->second.seq);
    }

    thread_local std::vector<uint8_t> scratch;
    if (!serialize_llm_stream_event(seq, p, scratch)) {
        return;
    }

    slot.fn(scratch.data(), scratch.size(), slot.user_data);
}

/**
 * @brief Legacy 9-arg overload — preserves source compatibility for
 *        `llm_component.cpp` and the unit tests. Forwards to the
 *        struct-based canonical dispatcher with session / progress
 *        fields left at proto3 defaults (identical wire output to the
 *        pre-unification 9-field shape).
 */
void dispatch_llm_stream_event(rac_handle_t handle,
                               const char*  token,
                               bool         is_final,
                               int          kind,
                               uint32_t     token_id,
                               float        logprob,
                               const char*  finish_reason,
                               const char*  error_message) {
    LLMStreamEventParams p;
    p.token         = token ? token : "";
    p.is_final      = is_final;
    p.kind          = kind;
    p.token_id      = token_id;
    p.logprob       = logprob;
    p.finish_reason = finish_reason;
    p.error_message = error_message;
    dispatch_llm_stream_event(handle, p);
}

}  // namespace rac::llm
