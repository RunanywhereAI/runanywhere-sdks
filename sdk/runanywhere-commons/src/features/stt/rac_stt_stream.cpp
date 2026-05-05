/**
 * @file rac_stt_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte STT stream ABI
 *        declared in `rac_stt_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids that the
 *     lifecycle manager owns. start() seeds a session, stop()/cancel()
 *     tear it down. Unloading a model SHOULD walk all sessions for the
 *     handle and cancel them — wired in via the lifecycle service when
 *     the SDK migration lands (CPP-03 follow-up).
 *   - dispatch_stt_stream_event() is invoked by stt_component.cpp and
 *     the streaming engines to emit serialized STTStreamEvent bytes.
 *
 * MVP scope:
 *   - Callback registration, session create/stop/cancel, and the dispatch
 *     helper are fully wired.
 *   - feed_audio_proto forwards the audio chunk bytes to
 *     rac_stt_component_transcribe_stream(). The bridging callback
 *     translates per-chunk partial / final emissions into
 *     STTStreamEvent proto bytes via dispatch_stt_stream_event().
 *     Backends that handle each chunk as a fresh transcription will see
 *     per-chunk partial+final pairs; backends that buffer internally will
 *     see streaming partials as expected.
 */

#include "rac/features/stt/rac_stt_stream.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "stt_options.pb.h"
#endif

namespace {

struct CallbackSlot {
    rac_stt_stream_proto_callback_fn fn        = nullptr;
    void*                            user_data = nullptr;
    uint64_t                         seq       = 0;
};

struct StreamSession {
    rac_handle_t handle    = nullptr;
    std::string  request_id;
    std::atomic<bool> is_cancelled{false};
    // Cached language code from STTOptions; nullptr means use defaults.
    // String storage owned by the session so the rac_stt_options_t we
    // build per feed_audio_proto can borrow it safely.
    std::string  language;
    int32_t      sample_rate = 16000;
    rac_audio_format_enum_t audio_format = RAC_AUDIO_FORMAT_PCM;
    bool         enable_punctuation = true;
    bool         enable_diarization = false;
    int32_t      max_speakers = 0;
    bool         enable_timestamps = true;
    bool         detect_language = false;
};

std::mutex& g_mu() { static std::mutex m; return m; }

std::unordered_map<rac_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_handle_t, CallbackSlot> m;
    return m;
}

std::unordered_map<uint64_t, StreamSession>& g_sessions() {
    static std::unordered_map<uint64_t, StreamSession> m;
    return m;
}

uint64_t next_session_id() {
    static std::atomic<uint64_t> g_counter{0};
    // Skip 0 — reserved as "invalid session" sentinel for SDK callers.
    return g_counter.fetch_add(1, std::memory_order_relaxed) + 1;
}

#if defined(RAC_HAVE_PROTOBUF)
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

const char* stt_language_code(runanywhere::v1::STTLanguage language) {
    switch (language) {
        case runanywhere::v1::STT_LANGUAGE_EN: return "en";
        case runanywhere::v1::STT_LANGUAGE_ES: return "es";
        case runanywhere::v1::STT_LANGUAGE_FR: return "fr";
        case runanywhere::v1::STT_LANGUAGE_DE: return "de";
        case runanywhere::v1::STT_LANGUAGE_ZH: return "zh";
        case runanywhere::v1::STT_LANGUAGE_JA: return "ja";
        case runanywhere::v1::STT_LANGUAGE_KO: return "ko";
        case runanywhere::v1::STT_LANGUAGE_IT: return "it";
        case runanywhere::v1::STT_LANGUAGE_PT: return "pt";
        case runanywhere::v1::STT_LANGUAGE_AR: return "ar";
        case runanywhere::v1::STT_LANGUAGE_RU: return "ru";
        case runanywhere::v1::STT_LANGUAGE_HI: return "hi";
        default: return nullptr;
    }
}

runanywhere::v1::STTLanguage stt_language_from_code(const char* code) {
    if (!code || code[0] == '\0') return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    if (std::strncmp(code, "en", 2) == 0) return runanywhere::v1::STT_LANGUAGE_EN;
    if (std::strncmp(code, "es", 2) == 0) return runanywhere::v1::STT_LANGUAGE_ES;
    if (std::strncmp(code, "fr", 2) == 0) return runanywhere::v1::STT_LANGUAGE_FR;
    if (std::strncmp(code, "de", 2) == 0) return runanywhere::v1::STT_LANGUAGE_DE;
    if (std::strncmp(code, "zh", 2) == 0) return runanywhere::v1::STT_LANGUAGE_ZH;
    if (std::strncmp(code, "ja", 2) == 0) return runanywhere::v1::STT_LANGUAGE_JA;
    if (std::strncmp(code, "ko", 2) == 0) return runanywhere::v1::STT_LANGUAGE_KO;
    if (std::strncmp(code, "it", 2) == 0) return runanywhere::v1::STT_LANGUAGE_IT;
    if (std::strncmp(code, "pt", 2) == 0) return runanywhere::v1::STT_LANGUAGE_PT;
    if (std::strncmp(code, "ar", 2) == 0) return runanywhere::v1::STT_LANGUAGE_AR;
    if (std::strncmp(code, "ru", 2) == 0) return runanywhere::v1::STT_LANGUAGE_RU;
    if (std::strncmp(code, "hi", 2) == 0) return runanywhere::v1::STT_LANGUAGE_HI;
    return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
}
#endif

}  // namespace

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::stt {
// Forward declaration: implemented later in this same TU. Used by
// rac_stt_stream_feed_audio_proto() to emit PARTIAL / FINAL events.
void dispatch_stt_stream_event(rac_handle_t                            handle,
                               runanywhere::v1::STTStreamEventKind     kind,
                               const runanywhere::v1::STTPartialResult* partial,
                               const runanywhere::v1::STTOutput*       final_output,
                               const char*                             error_message,
                               int                                     error_code);
}  // namespace rac::stt
#endif

extern "C" {

rac_result_t rac_stt_set_stream_proto_callback(rac_handle_t                     handle,
                                                rac_stt_stream_proto_callback_fn callback,
                                                void*                            user_data) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = CallbackSlot{ callback, user_data, /*seq=*/0 };
    }
    return RAC_SUCCESS;
}

rac_result_t rac_stt_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_stream_start_proto(rac_handle_t   handle,
                                         const uint8_t* options_proto_bytes,
                                         size_t         options_proto_size,
                                         uint64_t*      out_session_id) {
    if (handle == nullptr) return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr) return RAC_ERROR_NULL_POINTER;
    if (options_proto_size > 0 && options_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)options_proto_bytes;
    (void)options_proto_size;
    *out_session_id = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    runanywhere::v1::STTOptions parsed;
    if (options_proto_size > 0 &&
        !parsed.ParseFromArray(options_proto_bytes,
                                static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const uint64_t id = next_session_id();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        StreamSession& s = g_sessions()[id];
        s.handle = handle;
        s.request_id = "stt-" + std::to_string(id);
        s.is_cancelled.store(false, std::memory_order_relaxed);
        if (parsed.language() == runanywhere::v1::STT_LANGUAGE_AUTO) {
            s.detect_language = true;
        } else if (const char* code = stt_language_code(parsed.language())) {
            s.language = code;
        }
        s.enable_punctuation = parsed.enable_punctuation();
        s.enable_diarization = parsed.enable_diarization();
        s.max_speakers       = parsed.max_speakers();
        s.enable_timestamps  = parsed.enable_word_timestamps();
        s.sample_rate        = RAC_STT_DEFAULT_SAMPLE_RATE;
        s.audio_format       = RAC_AUDIO_FORMAT_PCM;
    }
    *out_session_id = id;
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_stt_stream_feed_audio_proto(uint64_t       session_id,
                                              const uint8_t* audio_bytes,
                                              size_t         audio_size) {
    if (session_id == 0) return RAC_ERROR_INVALID_ARGUMENT;
    if (audio_size > 0 && audio_bytes == nullptr) return RAC_ERROR_INVALID_ARGUMENT;

#if !defined(RAC_HAVE_PROTOBUF)
    (void)audio_bytes;
    (void)audio_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    // Snapshot session state under the lock — release before invoking the
    // long-running transcription so we don't hold g_mu() across user
    // callbacks. The session's request_id flows into each emitted event
    // through the bridging callback below.
    rac_handle_t component_handle = nullptr;
    std::string  language_buffer;
    bool         detect_language    = false;
    bool         enable_punctuation = true;
    bool         enable_diarization = false;
    int32_t      max_speakers       = 0;
    bool         enable_timestamps  = true;
    int32_t      sample_rate        = RAC_STT_DEFAULT_SAMPLE_RATE;
    rac_audio_format_enum_t audio_format = RAC_AUDIO_FORMAT_PCM;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end()) return RAC_ERROR_INVALID_ARGUMENT;
        if (it->second.is_cancelled.load(std::memory_order_relaxed)) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        component_handle   = it->second.handle;
        language_buffer    = it->second.language;
        detect_language    = it->second.detect_language;
        enable_punctuation = it->second.enable_punctuation;
        enable_diarization = it->second.enable_diarization;
        max_speakers       = it->second.max_speakers;
        enable_timestamps  = it->second.enable_timestamps;
        sample_rate        = it->second.sample_rate;
        audio_format       = it->second.audio_format;
    }
    if (component_handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (audio_size == 0) {
        return RAC_SUCCESS;
    }

    // Build per-call options. The language buffer lives in language_buffer
    // local until the transcribe call returns.
    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    options.language          = language_buffer.empty() ? nullptr : language_buffer.c_str();
    options.detect_language   = detect_language ? RAC_TRUE : RAC_FALSE;
    options.enable_punctuation = enable_punctuation ? RAC_TRUE : RAC_FALSE;
    options.enable_diarization = enable_diarization ? RAC_TRUE : RAC_FALSE;
    options.max_speakers       = max_speakers;
    options.enable_timestamps  = enable_timestamps ? RAC_TRUE : RAC_FALSE;
    options.sample_rate        = sample_rate;
    options.audio_format       = audio_format;

    // Bridge struct: forwards per-chunk transcribe_stream callbacks to the
    // proto-byte dispatch. We capture the language code by value so the
    // STTPartialResult / STTOutput payloads receive a stable language enum.
    struct BridgeCtx {
        rac_handle_t handle;
        runanywhere::v1::STTLanguage language;
        size_t       audio_size;
    } ctx{component_handle, stt_language_from_code(options.language), audio_size};

    auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
        auto* c = static_cast<BridgeCtx*>(opaque);
        runanywhere::v1::STTPartialResult partial;
        if (partial_text) {
            partial.set_text(partial_text);
        }
        partial.set_is_final(is_final == RAC_TRUE);
        partial.set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
        partial.set_language(c->language);

        if (is_final == RAC_TRUE) {
            runanywhere::v1::STTOutput final_output;
            if (partial_text) {
                final_output.set_text(partial_text);
            }
            final_output.set_language(c->language);
            rac::stt::dispatch_stt_stream_event(c->handle,
                                                runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL,
                                                &partial,
                                                &final_output,
                                                /*error_message=*/nullptr,
                                                /*error_code=*/0);
        } else {
            rac::stt::dispatch_stt_stream_event(c->handle,
                                                runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL,
                                                &partial,
                                                /*final_output=*/nullptr,
                                                /*error_message=*/nullptr,
                                                /*error_code=*/0);
        }
    };

    rac_result_t rc = rac_stt_component_transcribe_stream(
        component_handle, audio_bytes, audio_size, &options, bridge, &ctx);
    if (rc != RAC_SUCCESS) {
        rac::stt::dispatch_stt_stream_event(component_handle,
                                            runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
                                            /*partial=*/nullptr,
                                            /*final_output=*/nullptr,
                                            "STT streaming chunk failed",
                                            rc);
    }
    return rc;
#endif
}

rac_result_t rac_stt_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end()) return RAC_ERROR_INVALID_ARGUMENT;
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end()) return RAC_ERROR_INVALID_ARGUMENT;
    it->second.is_cancelled.store(true, std::memory_order_relaxed);
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

}  // extern "C"

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::stt {

/**
 * @brief Internal helper invoked by stt_component.cpp's streaming
 *        dispatcher per partial/final result. Serializes one
 *        STTStreamEvent and fires the registered callback.
 *
 * Available only when Protobuf is linked. Backends without Protobuf
 * fall back to the legacy struct callback path.
 *
 * Looks up the most recent active session bound to @p handle (if any) and
 * stamps its request_id on the emitted event so downstream consumers can
 * correlate partials and finals.
 */
void dispatch_stt_stream_event(rac_handle_t                            handle,
                               runanywhere::v1::STTStreamEventKind     kind,
                               const runanywhere::v1::STTPartialResult* partial,
                               const runanywhere::v1::STTOutput*       final_output,
                               const char*                             error_message,
                               int                                     error_code) {
    CallbackSlot slot;
    uint64_t seq = 0;
    std::string request_id;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr) return;
        slot = it->second;
        seq = ++(it->second.seq);
        for (const auto& [_, session] : g_sessions()) {
            if (session.handle == handle &&
                !session.is_cancelled.load(std::memory_order_relaxed)) {
                request_id = session.request_id;
                break;
            }
        }
    }

    thread_local runanywhere::v1::STTStreamEvent proto_event;
    thread_local std::vector<uint8_t>            scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    if (!request_id.empty()) {
        proto_event.set_request_id(request_id);
    }
    proto_event.set_kind(kind);
    if (partial) {
        *proto_event.mutable_partial() = *partial;
    }
    if (final_output) {
        *proto_event.mutable_final_output() = *final_output;
    }
    if (error_message && error_message[0] != '\0') {
        proto_event.set_error_message(error_message);
    }
    if (error_code != 0) {
        proto_event.set_error_code(error_code);
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed) scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("stt", "dispatch_stt_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::stt
#endif  // RAC_HAVE_PROTOBUF
