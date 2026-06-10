/**
 * @file rac_llm_stream_internal.h
 * @brief Canonical LLMStreamEvent emitter shared by
 *        `rac_llm_stream.cpp` (registry-backed callback path used by
 *        Swift iOS + Web via rac_llm_set_stream_proto_callback()) and
 *        `rac_llm_proto_service.cpp` (direct-callback path used by
 *        Kotlin Android JNI via rac_llm_generate_stream_proto()).
 *
 * Before this header existed the two call sites independently built
 * `runanywhere.v1.LLMStreamEvent` messages populating different subsets
 * of fields (9 vs. 13) — see BUG-STREAMING-001. This file now carries
 * the single canonical field set; both sinks call the same serializer
 * so every consumer sees the same 13 fields, with proto3 defaults
 * automatically filling any the caller does not supply.
 *
 * Internal header — not part of the public C ABI.
 */

#ifndef RAC_FEATURES_LLM_RAC_LLM_STREAM_INTERNAL_H
#define RAC_FEATURES_LLM_RAC_LLM_STREAM_INTERNAL_H

#include <cstddef>
#include <cstdint>
#include <vector>

#include "rac/core/rac_types.h"

#ifdef RAC_HAVE_PROTOBUF
#include "llm_service.pb.h"
#include "tool_calling.pb.h"
#endif

namespace rac::llm {

/**
 * @brief Complete field set for a single `runanywhere.v1.LLMStreamEvent`.
 *
 * Callers populate the fields they know; the rest remain proto3
 * defaults (0 / empty string / nullptr) and are omitted from the wire.
 * This keeps the 9-field wire shape emitted by the legacy
 * `llm_component.cpp` callers identical to before while allowing the
 * `rac_llm_proto_service.cpp` caller to populate the extra 4+ fields.
 */
struct LLMStreamEventParams {
    // Per-token scalars (always known by every caller).
    const char* token = "";
    bool is_final = false;
    int kind = 0;  // internal token kind (see to_proto_kind)
    uint32_t token_id = 0;
    float logprob = 0.0f;
    const char* finish_reason = nullptr;
    const char* error_message = nullptr;

    // Session / progress fields (only the proto_service path populates
    // these today; registry-path callers leave them at defaults).
    const char* request_id = nullptr;
    const char* conversation_id = nullptr;
    int32_t prompt_tokens_processed = 0;      // proto field 15
    int32_t completion_tokens_generated = 0;  // proto field 16
    int64_t elapsed_ms = 0;                   // proto field 17

    // Backend error code on terminal failure events; proto field 11.
    // 0 = unset/success (matches proto3 scalar default).
    int32_t error_code = 0;

    // Optional terminal aggregate result. Only populated on the
    // is_final=true event by callers that have access to libprotobuf
    // (proto_service path). When null, proto3 omits field 10.
#ifdef RAC_HAVE_PROTOBUF
    const runanywhere::v1::LLMStreamFinalResult* final_result = nullptr;
    // optional tool_call payload (proto field 18). Populated
    // by the tool-calling boundary-detection path in llm_component.cpp /
    // rac_llm_proto_service.cpp so streaming consumers can observe the tool
    // call inline with the token stream. NULL = omit (proto3 default).
    const runanywhere::v1::ToolCall* tool_call = nullptr;
#else
    const void* final_result = nullptr;  // unused without protobuf
    const void* tool_call = nullptr;     // unused without protobuf (WASM)
#endif
    // pre-serialized ToolCall bytes for the hand-encoded
    // (WASM) path. The protobuf path prefers the typed `tool_call` pointer
    // above; this fallback exists so a caller that has access to a
    // serialized ToolCall (e.g. via a side channel that already encoded it)
    // can emit proto field 18 even without linking libprotobuf into the
    // WASM bundle. NULL or zero size = omit (proto3 default).
    const uint8_t* tool_call_bytes = nullptr;
    size_t tool_call_bytes_size = 0;
};

/**
 * @brief Derive `LLMStreamEventKind` (proto field 12) from the per-token
 *        scalars. Mirrors the logic in `rac_llm_proto_service.cpp`
 *        (`event_kind_for_token`) so both paths classify events
 *        identically.
 *
 * Returns a plain int to avoid exposing the protobuf enum in headers
 * consumed by the hand-encoded WASM path (no libprotobuf there).
 */
int derive_event_kind(int kind, bool is_final, const char* error_message);

/**
 * @brief Serialize a `LLMStreamEvent` into the supplied vector.
 *
 * The protobuf build path uses the generated C++ API; the WASM path
 * uses a hand-rolled wire encoder (see rac_llm_stream.cpp). Both
 * branches write the same 13 fields so every SDK sees the full event.
 *
 * @param seq Per-stream monotonic sequence number (bumped by caller).
 * @param p   Field values to encode.
 * @param out Destination buffer — existing contents are cleared.
 * @return true on success, false on protobuf serialize failure.
 */
bool serialize_llm_stream_event(uint64_t seq, const LLMStreamEventParams& p,
                                std::vector<uint8_t>& out);

/**
 * @brief Registry-backed dispatcher used by `llm_component.cpp`.
 *
 * Looks up the per-handle callback registered via
 * `rac_llm_set_stream_proto_callback()`, bumps the per-handle sequence,
 * serializes the event via `serialize_llm_stream_event()`, then fires
 * the callback without holding the registry lock.
 */
void dispatch_llm_stream_event(rac_handle_t handle, const LLMStreamEventParams& p);

/**
 * @brief Legacy 9-arg dispatcher. Forwards to the struct-based overload
 *        so existing call sites in `llm_component.cpp` (and the unit
 *        tests) remain source-compatible. The 4 newer fields
 *        (`request_id`, `conversation_id`,
 *        `completion_tokens_generated`, `elapsed_ms`,
 *        `final_result`) stay at proto3 defaults on this path —
 *        identical wire output to the pre-unification 9-field shape.
 */
void dispatch_llm_stream_event(rac_handle_t handle, const char* token, bool is_final, int kind,
                               uint32_t token_id, float logprob, const char* finish_reason,
                               const char* error_message);

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_RAC_LLM_STREAM_INTERNAL_H
