/**
 * @file rac_llm_stream.cpp
 * @brief Implementation of the LLM proto-byte
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

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "features/llm/rac_llm_stream_internal.h"
#include "rac/core/rac_logger.h"

namespace {

// Lift the voice_agent in_flight quiesce pattern
// to the LLM proto-byte dispatcher. The dispatch_llm_stream_event() function
// copies the (callback, user_data) pair out of g_slots() under g_mu(), then
// drops the lock before invoking slot.fn(). A concurrent
// rac_llm_unset_stream_proto_callback() / rac_llm_component_destroy() can
// race the dispatch thread and free the user_data while slot.fn() is still
// running on another thread, yielding EXC_BAD_ACCESS in the trampoline (iOS
// Swift) or SIGSEGV in the std::function copy (RN Android/iOS). The in_flight
// counter is incremented under g_mu() once a live slot is found and decremented
// when dispatch_llm_stream_event() returns (so an unregistered handle never
// touches the atomic). rac_llm_proto_quiesce() spin-waits for the counter to
// drain to zero, exactly mirroring voice_agent.cpp:594 and
// rac_vlm_proto_abi.cpp:412.
static std::atomic<int> g_in_flight{0};

// Per-handle callback record. `seq` is the per-handle, per-session sequence
// counter (B-FL-7-001 fix): a single process-wide counter kept growing across
// generateStream calls and the Wire / protobuf-java decoder threw "end-group
// tag did not match" the second time on the same handle. seq resets to 0 on
// every fresh `set_stream_proto_callback` so each session starts at 1 again.
using CallbackSlot = rac::stream::CallbackSlot<rac_llm_stream_proto_callback_fn>;

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}
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

rac_result_t rac_llm_set_stream_proto_callback(rac_handle_t handle,
                                               rac_llm_stream_proto_callback_fn callback,
                                               void* user_data) {
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
        g_slots()[handle] = CallbackSlot{.fn = callback, .user_data = user_data, .seq = 0};
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

// Public quiesce helper. Callers (rac_llm_component_destroy, lifecycle
// teardown paths in SDK bridges) spin-wait here before freeing any
// user_data that may have been captured by a concurrent
// dispatch_llm_stream_event invocation. Mirrors rac_vlm_proto_quiesce().
void rac_llm_proto_quiesce(void) {
    while (g_in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
}

}  // extern "C"

namespace rac::llm {

int derive_event_kind(int kind, bool is_final, const char* error_message) {
    // Values match `runanywhere.v1.LLMStreamEventKind` in
    // idl/llm_service.proto. Encoded as int to keep this symbol
    // available on the hand-encoded (no-protobuf) WASM path.
    constexpr int kUnspecified = 0;
    constexpr int kToken = 2;
    constexpr int kThinking = 3;
    constexpr int kToolCall = 4;
    constexpr int kCompleted = 6;
    constexpr int kError = 7;
    constexpr int kTokenKindThought = 2;   // TOKEN_KIND_THOUGHT
    constexpr int kTokenKindToolCall = 3;  // TOKEN_KIND_TOOL_CALL

    if (is_final) {
        return (error_message && error_message[0] != '\0') ? kError : kCompleted;
    }
    if (kind == kTokenKindThought) {
        return kThinking;
    }
    // surface tool-call events on the canonical LLMStreamEvent
    // path. The proto-service producer emits an event with
    // kind=TOKEN_KIND_TOOL_CALL + tool_call payload when the tool-calling
    // parser detects a call mid-stream; LLM_STREAM_EVENT_KIND_TOOL_CALL is the
    // matching event_kind so consumers can branch on field 12 alone.
    if (kind == kTokenKindToolCall) {
        return kToolCall;
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
        case 1:
            return runanywhere::v1::TOKEN_KIND_ANSWER;
        case 2:
            return runanywhere::v1::TOKEN_KIND_THOUGHT;
        case 3:
            return runanywhere::v1::TOKEN_KIND_TOOL_CALL;
        default:
            return runanywhere::v1::TOKEN_KIND_UNSPECIFIED;
    }
}

bool serialize_llm_stream_event(uint64_t seq, const LLMStreamEventParams& p,
                                std::vector<uint8_t>& out) {
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
        proto_event.set_event_kind(static_cast<runanywhere::v1::LLMStreamEventKind>(event_kind));
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
    // emit proto field 18 (LLMStreamEvent.tool_call) when the
    // caller has detected a tool-call boundary mid-stream. NULL leaves the
    // field unset (proto3 default) so legacy text-only streams are byte-for-
    // byte identical to before.
    if (p.tool_call != nullptr) {
        *proto_event.mutable_tool_call() = *p.tool_call;
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (out.size() < needed)
        out.resize(needed);
    else
        out.resize(needed);
    if (needed > 0 && !proto_event.SerializeToArray(out.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("llm",
                        "serialize_llm_stream_event: SerializeToArray failed "
                        "(is_final=%d)",
                        p.is_final ? 1 : 0);
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
//  18: bytes  tool_call                   (length-delimited, pre-serialized
//                                          runanywhere.v1.ToolCall bytes via
//                                          LLMStreamEventParams::tool_call_bytes;
//                                          omitted when tool_call_bytes == NULL
//                                          or tool_call_bytes_size == 0)
//
// Field 10 (nested LLMStreamFinalResult) is NOT emitted on the
// hand-encoded path because no caller sets LLMStreamEventParams::final_result
// without libprotobuf (proto_service, the only populator of `result`,
// runs only with RAC_HAVE_PROTOBUF defined).
//
// Field 18 (nested runanywhere.v1.ToolCall) is emitted as opaque
// length-delimited bytes on this path: the libprotobuf build sets
// LLMStreamEventParams::tool_call (typed pointer) and the typed serializer
// writes field 18 via the generated message; the hand-encoded build accepts
// pre-serialized ToolCall bytes via LLMStreamEventParams::tool_call_bytes /
// tool_call_bytes_size and writes them directly. NULL / zero size omits the
// field (proto3 default).
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
    if (value == 0)
        return;  // proto3 default omission
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, value);
}

inline void wire_int64_field(std::vector<uint8_t>& out, uint32_t field, int64_t value) {
    if (value == 0)
        return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, static_cast<uint64_t>(value));  // varint, not zigzag (proto3 int64)
}

inline void wire_uint32_field(std::vector<uint8_t>& out, uint32_t field, uint32_t value) {
    if (value == 0)
        return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, value);
}

inline void wire_int32_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0)
        return;
    wire_tag(out, field, /*wire_type=*/0);
    // proto3 int32 uses plain varint (negative values are 10-byte sign-extended;
    // our callers only emit >= 0 values for token counters).
    wire_varint(out, static_cast<uint64_t>(value));
}

inline void wire_bool_field(std::vector<uint8_t>& out, uint32_t field, bool value) {
    if (!value)
        return;
    wire_tag(out, field, /*wire_type=*/0);
    out.push_back(0x01);
}

inline void wire_enum_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0)
        return;
    wire_tag(out, field, /*wire_type=*/0);
    wire_varint(out, static_cast<uint64_t>(value));
}

inline void wire_float_field(std::vector<uint8_t>& out, uint32_t field, float value) {
    if (value == 0.0f)
        return;
    wire_tag(out, field, /*wire_type=*/5);
    uint32_t bits;
    std::memcpy(&bits, &value, sizeof(bits));  // bit-cast (memcpy avoids strict-aliasing UB)
    out.push_back(static_cast<uint8_t>(bits & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 8) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 16) & 0xff));
    out.push_back(static_cast<uint8_t>((bits >> 24) & 0xff));
}

inline void wire_string_field(std::vector<uint8_t>& out, uint32_t field, const char* str) {
    if (str == nullptr || str[0] == '\0')
        return;
    const size_t len = std::strlen(str);
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, len);
    out.insert(out.end(), str, str + len);
}

// length-delimited bytes (wire type 2) for a pre-serialized
// nested message. Used for emitting LLMStreamEvent.tool_call (proto field
// 18) on the hand-encoded WASM path — the caller passes already-encoded
// ToolCall bytes (e.g. through a side channel that does have access to
// libprotobuf, or that hand-encoded the ToolCall itself).
inline void wire_bytes_field(std::vector<uint8_t>& out, uint32_t field, const uint8_t* bytes,
                             size_t size) {
    if (bytes == nullptr || size == 0)
        return;
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, size);
    out.insert(out.end(), bytes, bytes + size);
}

int32_t to_proto_kind_int(int internal_kind) {
    switch (internal_kind) {
        case 1:
            return 1;  // ANSWER
        case 2:
            return 2;  // THOUGHT
        case 3:
            return 3;  // TOOL_CALL
        default:
            return 0;  // UNSPECIFIED
    }
}

}  // namespace

namespace rac::llm {

bool serialize_llm_stream_event(uint64_t seq, const LLMStreamEventParams& p,
                                std::vector<uint8_t>& out) {
    out.clear();
    out.reserve(96);

    wire_uint64_field(out, /*field=*/1, seq);
    wire_int64_field(out, /*field=*/2, now_us());
    wire_string_field(out, /*field=*/3, p.token);
    wire_bool_field(out, /*field=*/4, p.is_final);
    wire_enum_field(out, /*field=*/5, to_proto_kind_int(p.kind));
    wire_uint32_field(out, /*field=*/6, p.token_id);
    wire_float_field(out, /*field=*/7, p.logprob);
    wire_string_field(out, /*field=*/8, p.finish_reason);
    wire_string_field(out, /*field=*/9, p.error_message);

    // Extended fields (BUG-STREAMING-001 fix). Nested `result` (field
    // 10) is intentionally not encoded on the hand-rolled path — no
    // caller sets `p.final_result` without libprotobuf.
    wire_int32_field(out, /*field=*/11, p.error_code);
    wire_enum_field(out, /*field=*/12, derive_event_kind(p.kind, p.is_final, p.error_message));
    wire_string_field(out, /*field=*/13, p.request_id);
    wire_string_field(out, /*field=*/14, p.conversation_id);
    wire_int32_field(out, /*field=*/15, p.prompt_tokens_processed);
    wire_int32_field(out, /*field=*/16, p.completion_tokens_generated);
    wire_int64_field(out, /*field=*/17, p.elapsed_ms);
    // tool_call (field 18) — length-delimited nested message.
    // The libprotobuf path uses `p.tool_call`; the hand-encoded path here
    // accepts pre-serialized bytes via `p.tool_call_bytes` so a caller that
    // already has encoded ToolCall bytes can still emit the field. NULL or
    // zero size omits per proto3 defaults.
    wire_bytes_field(out, /*field=*/18, p.tool_call_bytes, p.tool_call_bytes_size);

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
void dispatch_llm_stream_event(rac_handle_t handle, const LLMStreamEventParams& p) {
    // hold an InFlightGuard across the callback
    // fire so rac_llm_proto_quiesce() can be sure no slot.fn invocation is
    // still running before destroy/teardown frees user_data. The guard is
    // taken *inside* the registry lock, only once a live slot is found: an
    // unregistered handle returns before the atomic is touched (no wasted
    // barrier on the hot path for SDKs not using the proto callback), and
    // because the increment is ordered under g_mu() with the slot's presence,
    // a concurrent unset+quiesce either observes the in-flight count (we won
    // the lock) or finds an empty slot (it won — nothing to wait on).
    CallbackSlot slot;
    uint64_t seq;
    std::optional<rac::stream::InFlightGuard> in_flight_guard;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        in_flight_guard.emplace(g_in_flight);
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
void dispatch_llm_stream_event(rac_handle_t handle, const char* token, bool is_final, int kind,
                               uint32_t token_id, float logprob, const char* finish_reason,
                               const char* error_message) {
    LLMStreamEventParams p;
    p.token = token ? token : "";
    p.is_final = is_final;
    p.kind = kind;
    p.token_id = token_id;
    p.logprob = logprob;
    p.finish_reason = finish_reason;
    p.error_message = error_message;
    dispatch_llm_stream_event(handle, p);
}

}  // namespace rac::llm
