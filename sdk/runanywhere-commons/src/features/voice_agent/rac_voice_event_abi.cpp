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
 *   - When the library is built without Protobuf (no `RAC_HAVE_PROTOBUF`,
 *     e.g. Android), the implementation hand-encodes VoiceEvent into
 *     protobuf wire format. The schema is small + stable so this avoids
 *     pulling 12 MB of libprotobuf into every Android APK just for one
 *     message. Layout matches `idl/voice_events.proto` field-for-field.
 *     Mirrors the LLMStreamEvent fix in rac_llm_stream.cpp (Phase A,
 *     B-AK-4-001) — same root cause, same hand-encoder pattern.
 *
 * The actual hookup of `rac_voice_agent_set_proto_callback()` into the
 * agent's internal event dispatcher lives in voice_agent.cpp / the
 * pipeline EventDispatcher::emit() — they call dispatch_proto_event()
 * (declared in rac_voice_event_abi_internal.h) per event.
 */

#include "rac/features/voice_agent/rac_voice_event_abi.h"

#include "rac_voice_event_abi_internal.h"

#include "rac/core/rac_logger.h"

#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

/** Registered (callback, user_data) per handle. */
struct CallbackSlot {
    rac_voice_agent_proto_event_callback_fn fn        = nullptr;
    void*                                   user_data = nullptr;
    // Per-handle, per-session sequence counter. Mirrors the LLM stream fix
    // (B-FL-7-001): a process-wide counter caused decoders to reject the
    // second session on the same handle. Reset on every fresh registration
    // so each session starts at 1 again.
    uint64_t                                seq       = 0;
};

std::mutex&                                                 g_mu()    { static std::mutex m; return m; }
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

    // The registry path is identical with or without Protobuf — we only
    // diverge in how `dispatch_proto_event` serializes the event.
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        // Always start with seq = 0 for a fresh session.
        g_slots()[handle] = CallbackSlot{ callback, user_data, /*seq=*/0 };
    }
    return RAC_SUCCESS;
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

/* Translate a C struct event to a proto VoiceEvent. Maps the 7 C union
 * arms into the 8 proto oneof arms via the GAP 09 mapping table:
 *
 *   C event                          → proto VoiceEvent.payload
 *   ----------------------------------------------------------
 *   PROCESSED                        → metrics (terminal marker)
 *   VAD_TRIGGERED                    → vad
 *   TRANSCRIPTION                    → user_said
 *   RESPONSE                         → assistant_token (is_final=true)
 *   AUDIO_SYNTHESIZED                → audio
 *   ERROR                            → error
 *   WAKEWORD_DETECTED                → state (transition to LISTENING)
 *
 * Proto's `interrupted` arm has no current C-side producer; reserved
 * for the GAP 08 voice barge-in path.
 */
void translate(const rac_voice_agent_event_t& src, runanywhere::v1::VoiceEvent& dst) {
    dst.set_severity(src.type == RAC_VOICE_AGENT_EVENT_ERROR
                         ? runanywhere::v1::VOICE_EVENT_SEVERITY_ERROR
                         : runanywhere::v1::VOICE_EVENT_SEVERITY_INFO);
    switch (src.type) {
        case RAC_VOICE_AGENT_EVENT_PROCESSED: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_METRICS);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
            auto* m = dst.mutable_metrics();
            /* Per-primitive latencies are not yet captured in the C struct;
             * fill what we have and leave the rest at proto defaults. */
            m->set_tokens_generated(0);
            m->set_audio_samples_played(0);
            m->set_is_over_budget(false);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_VAD);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_VAD);
            auto* v = dst.mutable_vad();
            v->set_type(src.data.vad_speech_active == RAC_TRUE
                            ? runanywhere::v1::VAD_EVENT_VOICE_START
                            : runanywhere::v1::VAD_EVENT_VOICE_END_OF_UTTERANCE);
            v->set_frame_offset_us(0);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_TRANSCRIPTION: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_STT);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_STT);
            auto* u = dst.mutable_user_said();
            if (src.data.transcription) u->set_text(src.data.transcription);
            u->set_is_final(true);
            u->set_confidence(0.0f);
            u->set_audio_start_us(0);
            u->set_audio_end_us(0);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_RESPONSE: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_LLM);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_LLM);
            auto* t = dst.mutable_assistant_token();
            if (src.data.response) t->set_text(src.data.response);
            /* Voice-agent response events are full-utterance, so is_final
             * is true. Streaming token-level deltas come through GAP 09's
             * llm_service path, not this one. */
            t->set_is_final(true);
            t->set_kind(runanywhere::v1::TOKEN_KIND_ANSWER);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_TTS);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_TTS);
            auto* a = dst.mutable_audio();
            if (src.data.audio.audio_data && src.data.audio.audio_size > 0) {
                a->set_pcm(src.data.audio.audio_data, src.data.audio.audio_size);
            }
            /* Encoding metadata not yet plumbed through the C struct; the
             * agent emits 24kHz mono f32 today (Kokoro defaults). */
            a->set_sample_rate_hz(24000);
            a->set_channels(1);
            a->set_encoding(runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_ERROR: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_ERROR);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_AGENT);
            auto* e = dst.mutable_error();
            e->set_code(static_cast<int32_t>(src.data.error_code));
            e->set_message("");           /* C struct has no message string */
            e->set_component("pipeline"); /* C struct has no component string */
            e->set_is_recoverable(false); /* conservative default */
            break;
        }

        case RAC_VOICE_AGENT_EVENT_WAKEWORD_DETECTED: {
            dst.set_category(runanywhere::v1::VOICE_EVENT_CATEGORY_VOICE_AGENT);
            dst.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_WAKEWORD);
            /* No proto arm for wakeword today — surface as a state change
             * to LISTENING so frontends can react via the standard state
             * stream without losing the signal. */
            auto* s = dst.mutable_state();
            s->set_previous(runanywhere::v1::PIPELINE_STATE_IDLE);
            s->set_current(runanywhere::v1::PIPELINE_STATE_LISTENING);
            break;
        }
    }
}

}  // namespace

namespace rac::voice_agent {

/**
 * @brief Internal helper called by the voice agent's event dispatcher per
 *        emitted event. Serializes the C event struct into a
 *        runanywhere.v1.VoiceEvent + invokes the registered callback.
 *
 * Threading:
 *   - The (callback, user_data) pair is captured under the registry mutex
 *     so we do not hold the lock across the user callback (avoids deadlock
 *     if the callback re-enters rac_voice_agent_set_proto_callback).
 *   - The proto + serialization buffer are thread_local so concurrent
 *     dispatches on different threads do not contend on heap allocation.
 *     The arena reuse comes for free from `cc_enable_arenas` in
 *     voice_events.proto.
 */
void dispatch_proto_voice_event(rac_voice_agent_handle_t handle,
                                const runanywhere::v1::VoiceEvent& event) {
    CallbackSlot slot;
    uint64_t     seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        // Bump the per-handle counter under the lock so concurrent dispatches
        // on the same handle still produce monotonic seq values.
        seq = ++(it->second.seq);
    }

    thread_local std::vector<uint8_t>        scratch;

    runanywhere::v1::VoiceEvent proto_event(event);
    if (proto_event.seq() == 0) {
        proto_event.set_seq(seq);
    }
    if (proto_event.timestamp_us() == 0) {
        proto_event.set_timestamp_us(now_us());
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed) scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        /* Serialization should never fail for a valid message; log and
         * drop instead of crashing. */
        RAC_LOG_WARNING("voice_agent",
                        "dispatch_proto_event: SerializeToArray failed for payload case=%d",
                        static_cast<int>(proto_event.payload_case()));
        return;
    }

    slot.fn(scratch.data(), needed, slot.user_data);
}

void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                           const rac_voice_agent_event_t* event) {
    if (event == nullptr) return;

    runanywhere::v1::VoiceEvent proto_event;
    translate(*event, proto_event);
    dispatch_proto_voice_event(handle, proto_event);
}

}  // namespace rac::voice_agent

#else /* RAC_HAVE_PROTOBUF not defined */

// =============================================================================
// Hand-encoded protobuf wire format for runanywhere.v1.VoiceEvent.
//
// We avoid linking libprotobuf on Android (saves ~12 MB per app, and the
// NDK does not ship Protobuf out of the box) by serializing this message
// manually. Wire format reference:
//   https://protobuf.dev/programming-guides/encoding/
//
// Field numbers and types must match `idl/voice_events.proto`:
//
//   message VoiceEvent {
//     uint64 seq            = 1;   // varint
//     int64  timestamp_us   = 2;   // varint
//     oneof payload {              // each is a length-delimited submessage
//       UserSaidEvent       user_said       = 10;
//       AssistantTokenEvent assistant_token = 11;
//       AudioFrameEvent     audio           = 12;
//       VADEvent            vad             = 13;
//       InterruptedEvent    interrupted     = 14;   // (no producer today)
//       StateChangeEvent    state           = 15;
//       ErrorEvent          error           = 16;
//       MetricsEvent        metrics         = 17;
//     }
//   }
//
// proto3 default-value omission semantics are preserved: scalars equal to
// their type's default (0, false, empty string) are skipped on the wire.
// Nested messages, however, MUST be emitted whenever the oneof arm is
// selected even if all sub-fields are at default — otherwise the decoder
// cannot tell the oneof was set.
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

inline void wire_int32_field(std::vector<uint8_t>& out, uint32_t field, int32_t value) {
    if (value == 0) return;
    wire_tag(out, field, /*wire_type=*/0);
    /* proto3 int32 encodes negative values as 10-byte varint via sign
     * extension to 64 bits. Cast through int64 first to preserve the
     * sign bits. */
    wire_varint(out, static_cast<uint64_t>(static_cast<int64_t>(value)));
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

inline void wire_double_field(std::vector<uint8_t>& out, uint32_t field, double value) {
    if (value == 0.0) return;
    wire_tag(out, field, /*wire_type=*/1);  // fixed64
    uint64_t bits;
    std::memcpy(&bits, &value, sizeof(bits));  // bit-cast (memcpy avoids strict-aliasing UB)
    for (int i = 0; i < 8; ++i) {
        out.push_back(static_cast<uint8_t>((bits >> (i * 8)) & 0xff));
    }
}

inline void wire_string_field(std::vector<uint8_t>& out, uint32_t field, const char* str) {
    if (str == nullptr || str[0] == '\0') return;
    const size_t len = std::strlen(str);
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, len);
    out.insert(out.end(), str, str + len);
}

inline void wire_string_field_force(std::vector<uint8_t>& out, uint32_t field, const char* str) {
    /* Variant that emits the string even when empty. Used for fixed
     * "component" tags inside ErrorEvent so frontends always see the
     * field set. */
    if (str == nullptr) return;
    const size_t len = std::strlen(str);
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, len);
    if (len > 0) {
        out.insert(out.end(), str, str + len);
    }
}

inline void wire_bytes_field(std::vector<uint8_t>& out, uint32_t field,
                             const void* data, size_t size) {
    if (data == nullptr || size == 0) return;
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, size);
    const auto* p = static_cast<const uint8_t*>(data);
    out.insert(out.end(), p, p + size);
}

/* Emit a length-delimited submessage at @p field. The submessage body is
 * built into a thread_local scratch by @p build, then framed into @p out.
 * Always emitted (even when body is empty) because oneof arms must be
 * present for the decoder to pick the right arm. */
template <typename Build>
void wire_submessage(std::vector<uint8_t>& out, uint32_t field, Build&& build) {
    thread_local std::vector<uint8_t> sub;
    sub.clear();
    build(sub);
    wire_tag(out, field, /*wire_type=*/2);
    wire_varint(out, sub.size());
    out.insert(out.end(), sub.begin(), sub.end());
}

// ---------------------------------------------------------------------------
// Submessage encoders. Field numbers + types match idl/voice_events.proto.
// ---------------------------------------------------------------------------

void encode_user_said(std::vector<uint8_t>& s, const char* text) {
    /*  1: string text             */
    wire_string_field(s, 1, text);
    /*  2: bool   is_final         (always true for full-utterance) */
    wire_bool_field  (s, 2, true);
    /*  3: float  confidence       (default 0.0f → omitted) */
    /*  4: int64  audio_start_us   (default 0    → omitted) */
    /*  5: int64  audio_end_us     (default 0    → omitted) */
}

void encode_assistant_token(std::vector<uint8_t>& s, const char* text) {
    /*  1: string text             */
    wire_string_field(s, 1, text);
    /*  2: bool   is_final         */
    wire_bool_field  (s, 2, true);
    /*  3: enum   kind             (1 = TOKEN_KIND_ANSWER) */
    wire_enum_field  (s, 3, 1);
}

void encode_audio_frame(std::vector<uint8_t>& s,
                        const void* pcm, size_t pcm_size) {
    /*  1: bytes pcm              */
    wire_bytes_field (s, 1, pcm, pcm_size);
    /*  2: int32 sample_rate_hz   (24000) */
    wire_int32_field (s, 2, 24000);
    /*  3: int32 channels         (1) */
    wire_int32_field (s, 3, 1);
    /*  4: enum  encoding         (1 = AUDIO_ENCODING_PCM_F32_LE) */
    wire_enum_field  (s, 4, 1);
}

void encode_vad(std::vector<uint8_t>& s, bool speech_active) {
    /*  1: enum type
     *     1 = VAD_EVENT_VOICE_START
     *     2 = VAD_EVENT_VOICE_END_OF_UTTERANCE  */
    wire_enum_field  (s, 1, speech_active ? 1 : 2);
    /*  2: int64 frame_offset_us (default 0 → omitted) */
}

void encode_state_change(std::vector<uint8_t>& s,
                         int32_t previous, int32_t current) {
    /*  1: enum previous          */
    wire_enum_field  (s, 1, previous);
    /*  2: enum current           */
    wire_enum_field  (s, 2, current);
}

void encode_error(std::vector<uint8_t>& s, int32_t code) {
    /*  1: int32  code            */
    wire_int32_field (s, 1, code);
    /*  2: string message         (empty → omitted) */
    /*  3: string component       (always "pipeline" so the frontend can
     *                             route by component without a guard) */
    wire_string_field(s, 3, "pipeline");
    /*  4: bool   is_recoverable  (false → omitted) */
}

void encode_metrics(std::vector<uint8_t>& /*s*/) {
    /*  1: double stt_final_ms       (0 → omitted)
     *  2: double llm_first_token_ms (0 → omitted)
     *  3: double tts_first_audio_ms (0 → omitted)
     *  4: double end_to_end_ms      (0 → omitted)
     *  5: int64  tokens_generated   (0 → omitted)
     *  6: int64  audio_samples_played (0 → omitted)
     *  7: bool   is_over_budget     (false → omitted)
     *  8: int64  created_at_ns      (0 → omitted)
     *
     * The C struct has none of these populated yet, so the submessage is
     * empty. The frame's outer length-prefix (wire_submessage) still
     * carries enough information for the decoder to recognize the oneof
     * arm. */
}

}  // namespace

namespace rac::voice_agent {

void dispatch_proto_voice_event(rac_voice_agent_handle_t,
                                const runanywhere::v1::VoiceEvent&) {
    // Generated VoiceEvent dispatch is only available when libprotobuf is linked.
}

/**
 * @brief Internal helper called by the voice agent's event dispatcher per
 *        emitted event. Serializes the C event struct into a
 *        runanywhere.v1.VoiceEvent (hand-encoded wire format) + invokes
 *        the registered callback.
 *
 * Threading: the (callback, user_data) pair is captured under the registry
 * mutex but the lock is NOT held across the user callback (avoids deadlock
 * if the callback re-enters rac_voice_agent_set_proto_callback). The
 * scratch buffer is thread_local so concurrent dispatches on different
 * threads do not contend on heap allocation.
 */
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                           const rac_voice_agent_event_t* event) {
    if (event == nullptr) return;

    CallbackSlot slot;
    uint64_t     seq;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        seq = ++(it->second.seq);
    }

    thread_local std::vector<uint8_t> scratch;
    scratch.clear();
    scratch.reserve(64);

    /* Top-level VoiceEvent header. */
    wire_uint64_field(scratch, 1, seq);
    wire_int64_field (scratch, 2, now_us());

    /* Oneof payload — exactly one arm per event. Field numbers below match
     * idl/voice_events.proto; the C → proto routing matches the existing
     * RAC_HAVE_PROTOBUF translate() above. */
    switch (event->type) {
        case RAC_VOICE_AGENT_EVENT_PROCESSED:
            wire_submessage(scratch, /*field=*/17, [](std::vector<uint8_t>& s) {
                encode_metrics(s);
            });
            break;

        case RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED: {
            const bool speech_active = (event->data.vad_speech_active == RAC_TRUE);
            wire_submessage(scratch, /*field=*/13, [&](std::vector<uint8_t>& s) {
                encode_vad(s, speech_active);
            });
            break;
        }

        case RAC_VOICE_AGENT_EVENT_TRANSCRIPTION: {
            const char* text = event->data.transcription;
            wire_submessage(scratch, /*field=*/10, [&](std::vector<uint8_t>& s) {
                encode_user_said(s, text);
            });
            break;
        }

        case RAC_VOICE_AGENT_EVENT_RESPONSE: {
            const char* text = event->data.response;
            wire_submessage(scratch, /*field=*/11, [&](std::vector<uint8_t>& s) {
                encode_assistant_token(s, text);
            });
            break;
        }

        case RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED: {
            const void* pcm  = event->data.audio.audio_data;
            const size_t len = event->data.audio.audio_size;
            wire_submessage(scratch, /*field=*/12, [&](std::vector<uint8_t>& s) {
                encode_audio_frame(s, pcm, len);
            });
            break;
        }

        case RAC_VOICE_AGENT_EVENT_ERROR: {
            const int32_t code = static_cast<int32_t>(event->data.error_code);
            wire_submessage(scratch, /*field=*/16, [&](std::vector<uint8_t>& s) {
                encode_error(s, code);
            });
            break;
        }

        case RAC_VOICE_AGENT_EVENT_WAKEWORD_DETECTED:
            /* Surface as IDLE → LISTENING (matches the protobuf path). */
            wire_submessage(scratch, /*field=*/15, [](std::vector<uint8_t>& s) {
                encode_state_change(s, /*previous=*/1, /*current=*/2);
            });
            break;
    }

    slot.fn(scratch.data(), scratch.size(), slot.user_data);
}

}  // namespace rac::voice_agent

#endif  /* RAC_HAVE_PROTOBUF */
