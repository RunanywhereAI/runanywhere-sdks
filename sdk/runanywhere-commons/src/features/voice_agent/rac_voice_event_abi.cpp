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

#include "voice_events.pb.h"

#include <atomic>
#include <chrono>
#include <vector>

namespace {

/* Monotonic per-process sequence counter for VoiceEvent.seq. The proto
 * field is uint64; we wrap on overflow. */
std::atomic<uint64_t> g_seq_counter{0};

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
    dst.set_seq(g_seq_counter.fetch_add(1, std::memory_order_relaxed) + 1);
    dst.set_timestamp_us(now_us());

    switch (src.type) {
        case RAC_VOICE_AGENT_EVENT_PROCESSED: {
            auto* m = dst.mutable_metrics();
            /* Per-primitive latencies are not yet captured in the C struct;
             * fill what we have and leave the rest at proto defaults. */
            m->set_tokens_generated(0);
            m->set_audio_samples_played(0);
            m->set_is_over_budget(false);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED: {
            auto* v = dst.mutable_vad();
            v->set_type(src.data.vad_speech_active == RAC_TRUE
                            ? runanywhere::v1::VAD_EVENT_VOICE_START
                            : runanywhere::v1::VAD_EVENT_VOICE_END_OF_UTTERANCE);
            v->set_frame_offset_us(0);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_TRANSCRIPTION: {
            auto* u = dst.mutable_user_said();
            if (src.data.transcription) u->set_text(src.data.transcription);
            u->set_is_final(true);
            u->set_confidence(0.0f);
            u->set_audio_start_us(0);
            u->set_audio_end_us(0);
            break;
        }

        case RAC_VOICE_AGENT_EVENT_RESPONSE: {
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
            auto* e = dst.mutable_error();
            e->set_code(static_cast<int32_t>(src.data.error_code));
            e->set_message("");           /* C struct has no message string */
            e->set_component("pipeline"); /* C struct has no component string */
            e->set_is_recoverable(false); /* conservative default */
            break;
        }

        case RAC_VOICE_AGENT_EVENT_WAKEWORD_DETECTED: {
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
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                           const rac_voice_agent_event_t* event) {
    if (event == nullptr) return;

    CallbackSlot slot;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
    }

    thread_local runanywhere::v1::VoiceEvent proto_event;
    thread_local std::vector<uint8_t>        scratch;

    proto_event.Clear();
    translate(*event, proto_event);

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed) scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        /* Serialization should never fail for a valid message; log and
         * drop instead of crashing. */
        RAC_LOG_WARNING("voice_agent",
                        "dispatch_proto_event: SerializeToArray failed for event type=%d",
                        static_cast<int>(event->type));
        return;
    }

    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::voice_agent

#else /* RAC_HAVE_PROTOBUF not defined */

namespace rac::voice_agent {
/* No-op when Protobuf is not compiled in — the registration call returned
 * RAC_ERROR_FEATURE_NOT_AVAILABLE so g_slots() is always empty. */
void dispatch_proto_event(rac_voice_agent_handle_t       /*handle*/,
                           const rac_voice_agent_event_t* /*event*/) {}
}  // namespace rac::voice_agent

#endif  /* RAC_HAVE_PROTOBUF */
