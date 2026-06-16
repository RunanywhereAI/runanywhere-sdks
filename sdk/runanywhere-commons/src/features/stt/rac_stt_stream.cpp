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
 *     the SDK migration lands.
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
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "infrastructure/events/sdk_event_publish.h"
#include "sdk_events.pb.h"
#include "stt_options.pb.h"
#endif

namespace {

// Lift the voice_agent in_flight quiesce pattern
// to the STT proto-byte dispatcher. See rac_llm_stream.cpp and
// rac_vlm_proto_abi.cpp for the canonical reference; this guards
// dispatch_stt_stream_event so destroy/teardown can spin-wait until any
// in-flight slot.fn() returns before freeing user_data.
std::atomic<int> g_in_flight{0};

struct StreamSession {
    rac_handle_t handle = nullptr;
    std::string request_id;
    std::atomic<bool> is_cancelled{false};
    // Cached language code from STTOptions; nullptr means use defaults.
    // String storage owned by the session so the rac_stt_options_t we
    // build per feed_audio_proto can borrow it safely.
    std::string language;
    int32_t sample_rate = 16000;
    rac_audio_format_enum_t audio_format = RAC_AUDIO_FORMAT_PCM;
    bool enable_punctuation = true;
    bool enable_diarization = false;
    int32_t max_speakers = 0;
    bool enable_timestamps = true;
    bool detect_language = false;
    // Per-session backend recognizer handle. Lazily created on the
    // first accepted audio chunk via the new stream_create vtable slot.
    // Backends that don't implement the slot leave this nullptr and
    // rac_stt_stream_feed_audio_proto falls back to the legacy per-chunk
    // transcribe_stream path.
    rac_handle_t backend_stream_handle = nullptr;
    bool backend_stream_unsupported = false;
    // Session aggregates for the ONE telemetry summary emitted at stop —
    // per-chunk events are PUBLIC-only so a live session does not produce a
    // telemetry row (and an HTTP flush) per chunk.
    int64_t started_at_ms = 0;
    uint64_t chunks_fed = 0;
    uint64_t audio_bytes = 0;
};

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}

std::unordered_map<rac_handle_t, rac::stream::CallbackSlot<rac_stt_stream_proto_callback_fn>>&
g_slots() {
    static std::unordered_map<rac_handle_t,
                              rac::stream::CallbackSlot<rac_stt_stream_proto_callback_fn>>
        m;
    return m;
}

std::unordered_map<uint64_t, StreamSession>& g_sessions() {
    static std::unordered_map<uint64_t, StreamSession> m;
    return m;
}

// One allocator instance per TU keeps an independent id sequence; next() skips
// 0, reserved as the "invalid session" sentinel for SDK callers.
rac::stream::SessionIdAllocator g_session_ids;

#if defined(RAC_HAVE_PROTOBUF)
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

const char* stt_language_code(runanywhere::v1::STTLanguage language) {
    switch (language) {
        case runanywhere::v1::STT_LANGUAGE_EN:
            return "en";
        case runanywhere::v1::STT_LANGUAGE_ES:
            return "es";
        case runanywhere::v1::STT_LANGUAGE_FR:
            return "fr";
        case runanywhere::v1::STT_LANGUAGE_DE:
            return "de";
        case runanywhere::v1::STT_LANGUAGE_ZH:
            return "zh";
        case runanywhere::v1::STT_LANGUAGE_JA:
            return "ja";
        case runanywhere::v1::STT_LANGUAGE_KO:
            return "ko";
        case runanywhere::v1::STT_LANGUAGE_IT:
            return "it";
        case runanywhere::v1::STT_LANGUAGE_PT:
            return "pt";
        case runanywhere::v1::STT_LANGUAGE_AR:
            return "ar";
        case runanywhere::v1::STT_LANGUAGE_RU:
            return "ru";
        case runanywhere::v1::STT_LANGUAGE_HI:
            return "hi";
        default:
            return nullptr;
    }
}

runanywhere::v1::STTLanguage stt_language_from_code(const char* code) {
    if (!code || code[0] == '\0')
        return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    if (std::strncmp(code, "en", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_EN;
    if (std::strncmp(code, "es", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_ES;
    if (std::strncmp(code, "fr", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_FR;
    if (std::strncmp(code, "de", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_DE;
    if (std::strncmp(code, "zh", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_ZH;
    if (std::strncmp(code, "ja", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_JA;
    if (std::strncmp(code, "ko", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_KO;
    if (std::strncmp(code, "it", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_IT;
    if (std::strncmp(code, "pt", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_PT;
    if (std::strncmp(code, "ar", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_AR;
    if (std::strncmp(code, "ru", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_RU;
    if (std::strncmp(code, "hi", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_HI;
    return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
}
#endif

}  // namespace

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::stt {
// Forward declaration: implemented later in this same TU. Used by
// rac_stt_stream_feed_audio_proto() to emit PARTIAL / FINAL events.
// session_id correlates the emitted event with the originating session so
// concurrent sessions on the same component handle do not cross-pollinate
// request_ids. A session_id of 0 falls
// back to the legacy handle-scan path used by error emissions where the
// session context is not threaded.
void dispatch_stt_stream_event(rac_handle_t handle, runanywhere::v1::STTStreamEventKind kind,
                               const runanywhere::v1::STTPartialResult* partial,
                               const runanywhere::v1::STTOutput* final_output,
                               const char* error_message, int error_code, uint64_t session_id = 0);
}  // namespace rac::stt
#endif

extern "C" {

rac_result_t rac_stt_set_stream_proto_callback(rac_handle_t handle,
                                               rac_stt_stream_proto_callback_fn callback,
                                               void* user_data) {
    if (handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = rac::stream::CallbackSlot<rac_stt_stream_proto_callback_fn>{
            .fn = callback, .user_data = user_data, .seq = 0};
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

// Public quiesce helper. Mirrors
// rac_vlm_proto_quiesce / rac_llm_proto_quiesce. Spin-waits until every
// in-flight dispatch_stt_stream_event invocation has returned. Callers
// freeing user_data registered via rac_stt_set_stream_proto_callback, or
// tearing down the STT component, MUST call this after the unset to avoid
// a use-after-free in the dispatch thread.
void rac_stt_proto_quiesce(void) {
    while (g_in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
}

rac_result_t rac_stt_stream_start_proto(rac_handle_t handle, const uint8_t* options_proto_bytes,
                                        size_t options_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
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
        !parsed.ParseFromArray(options_proto_bytes, static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const uint64_t id = g_session_ids.next();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        StreamSession& s = g_sessions()[id];
        s.handle = handle;
        s.request_id = "stt-" + std::to_string(id);
        s.is_cancelled.store(false, std::memory_order_relaxed);
        s.started_at_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::system_clock::now().time_since_epoch())
                              .count();
        // Honor every STTOptions field
        // the C ABI's rac_stt_options_t can carry. Previously this dropped
        // language_code, sample_rate, audio_format, and detect_language
        // before they could reach the backend stream_create / feed_audio
        // calls, which made the streaming path silently inconsistent with
        // the one-shot rac_stt_component_process_proto path.
        if (parsed.language() == runanywhere::v1::STT_LANGUAGE_AUTO) {
            s.detect_language = true;
        } else if (const char* code = stt_language_code(parsed.language())) {
            s.language = code;
        }
        // The free-form BCP-47 language_code wins over the enum-derived
        // language when set, matching the proto comment ("consumers should
        // prefer this over the base-language enum").
        if (!parsed.language_code().empty()) {
            s.language = parsed.language_code();
        }
        // Explicit detect_language flag overrides the STT_LANGUAGE_AUTO
        // shorthand so generated-only consumers can request auto-detect
        // alongside a hint language.
        if (parsed.detect_language()) {
            s.detect_language = true;
        }
        s.enable_punctuation = parsed.enable_punctuation();
        s.enable_diarization = parsed.enable_diarization();
        s.max_speakers = parsed.max_speakers();
        s.enable_timestamps = parsed.enable_word_timestamps();
        // Fall back to defaults when the proto field is unset (0 for
        // sample_rate, AUDIO_FORMAT_UNSPECIFIED for audio_format).
        s.sample_rate =
            parsed.sample_rate() > 0 ? parsed.sample_rate() : RAC_STT_DEFAULT_SAMPLE_RATE;
        switch (parsed.audio_format()) {
            case runanywhere::v1::AUDIO_FORMAT_WAV:
                s.audio_format = RAC_AUDIO_FORMAT_WAV;
                break;
            case runanywhere::v1::AUDIO_FORMAT_MP3:
                s.audio_format = RAC_AUDIO_FORMAT_MP3;
                break;
            case runanywhere::v1::AUDIO_FORMAT_OPUS:
                s.audio_format = RAC_AUDIO_FORMAT_OPUS;
                break;
            case runanywhere::v1::AUDIO_FORMAT_AAC:
                s.audio_format = RAC_AUDIO_FORMAT_AAC;
                break;
            case runanywhere::v1::AUDIO_FORMAT_FLAC:
                s.audio_format = RAC_AUDIO_FORMAT_FLAC;
                break;
            case runanywhere::v1::AUDIO_FORMAT_PCM:
            case runanywhere::v1::AUDIO_FORMAT_PCM_S16LE:
            case runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED:
            default:
                // Container formats with no C enum equivalent (OGG, M4A) and
                // proto3 unset default both map to PCM, mirroring
                // audio_format_from_proto() in rac_proto_adapters.cpp.
                s.audio_format = RAC_AUDIO_FORMAT_PCM;
                break;
        }
        // STTOptions.beam_size and .max_alternatives have no equivalent slots
        // on rac_stt_options_t today; backends that need them must surface
        // them through STTConfiguration.
    }
    *out_session_id = id;
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_stt_stream_feed_audio_proto(uint64_t session_id, const uint8_t* audio_bytes,
                                             size_t audio_size) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (audio_size > 0 && audio_bytes == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;

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
    std::string language_buffer;
    bool detect_language = false;
    bool enable_punctuation = true;
    bool enable_diarization = false;
    int32_t max_speakers = 0;
    bool enable_timestamps = true;
    int32_t sample_rate = RAC_STT_DEFAULT_SAMPLE_RATE;
    rac_audio_format_enum_t audio_format = RAC_AUDIO_FORMAT_PCM;
    rac_handle_t backend_stream_handle = nullptr;
    bool backend_stream_unsupported = false;
    std::string request_id;
    bool first_chunk = false;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        if (it->second.is_cancelled.load(std::memory_order_relaxed)) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        component_handle = it->second.handle;
        language_buffer = it->second.language;
        detect_language = it->second.detect_language;
        enable_punctuation = it->second.enable_punctuation;
        enable_diarization = it->second.enable_diarization;
        max_speakers = it->second.max_speakers;
        enable_timestamps = it->second.enable_timestamps;
        sample_rate = it->second.sample_rate;
        audio_format = it->second.audio_format;
        backend_stream_handle = it->second.backend_stream_handle;
        backend_stream_unsupported = it->second.backend_stream_unsupported;
        request_id = it->second.request_id;
        if (audio_size > 0) {
            // Aggregate for the one summary telemetry row emitted at stop.
            first_chunk = (it->second.chunks_fed == 0);
            it->second.chunks_fed += 1;
            it->second.audio_bytes += audio_size;
        }
    }
    if (component_handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (audio_size == 0) {
        return RAC_SUCCESS;
    }

    // Session-level started — pairs with the one STT_COMPLETED summary emitted
    // at stop so the dashboard sees a started/completed pair per stream
    // session (per-chunk events are PUBLIC-only).
    if (first_chunk) {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_TRANSCRIPTION_STARTED);
        if (component_handle) {
            if (const char* model_id = rac_stt_component_get_model_id(component_handle)) {
                voice.set_model_id(model_id);
            }
        }
        voice.set_is_streaming(true);
        if (!language_buffer.empty()) {
            voice.set_language(language_buffer);
        }
        if (sample_rate > 0) {
            voice.set_sample_rate(sample_rate);
        }
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          request_id.c_str());
    }

    // Build per-call options. The language buffer lives in language_buffer
    // local until the transcribe call returns.
    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    options.language = language_buffer.empty() ? nullptr : language_buffer.c_str();
    options.detect_language = detect_language ? RAC_TRUE : RAC_FALSE;
    options.enable_punctuation = enable_punctuation ? RAC_TRUE : RAC_FALSE;
    options.enable_diarization = enable_diarization ? RAC_TRUE : RAC_FALSE;
    options.max_speakers = max_speakers;
    options.enable_timestamps = enable_timestamps ? RAC_TRUE : RAC_FALSE;
    options.sample_rate = sample_rate;
    options.audio_format = audio_format;

    // Try the persistent-handle path first. Backends that advertise
    // stream_create + stream_feed_audio_chunk keep their recognizer state
    // alive for the whole session. On first chunk we lazily spin up the
    // backend stream; subsequent chunks reuse the handle until the session
    // is stopped or cancelled.
    if (!backend_stream_unsupported) {
        if (backend_stream_handle == nullptr) {
            rac_handle_t new_stream = nullptr;
            rac_result_t create_rc =
                rac_stt_component_stream_create(component_handle, &options, &new_stream);
            if (create_rc == RAC_SUCCESS && new_stream != nullptr) {
                std::lock_guard<std::mutex> lock(g_mu());
                auto it = g_sessions().find(session_id);
                if (it == g_sessions().end() ||
                    it->second.is_cancelled.load(std::memory_order_relaxed)) {
                    // Session torn down while we were creating — drop the
                    // freshly-allocated backend handle so we don't leak.
                    (void)rac_stt_component_stream_destroy(component_handle, new_stream);
                    return RAC_ERROR_INVALID_ARGUMENT;
                }
                // Another concurrent feed may have raced us; keep the
                // first-in-wins handle and destroy ours if so.
                if (it->second.backend_stream_handle != nullptr) {
                    (void)rac_stt_component_stream_destroy(component_handle, new_stream);
                    backend_stream_handle = it->second.backend_stream_handle;
                } else {
                    it->second.backend_stream_handle = new_stream;
                    backend_stream_handle = new_stream;
                }
            } else if (create_rc == RAC_ERROR_NOT_SUPPORTED) {
                // Backend didn't wire the new slot — remember so subsequent
                // chunks skip the create probe and take the legacy path
                // straight away.
                std::lock_guard<std::mutex> lock(g_mu());
                auto it = g_sessions().find(session_id);
                if (it != g_sessions().end()) {
                    it->second.backend_stream_unsupported = true;
                }
            } else {
                rac::stt::dispatch_stt_stream_event(
                    component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
                    /*partial=*/nullptr, /*final_output=*/nullptr, "STT streaming start failed",
                    create_rc, session_id);
                return create_rc;
            }
        }

        if (backend_stream_handle != nullptr) {
            // audio_size is in bytes; convert to Int16 sample count. We
            // assume Int16 PCM mono — matches rac_audio_format_enum_t /
            // RAC_AUDIO_FORMAT_PCM which every current STT backend expects.
            const int16_t* samples = reinterpret_cast<const int16_t*>(audio_bytes);
            const size_t count = audio_size / sizeof(int16_t);

            struct BridgeCtxStream {
                rac_handle_t handle;
                runanywhere::v1::STTLanguage language;
                uint64_t session_id;
            } ctx{.handle = component_handle,
                  .language = stt_language_from_code(options.language),
                  .session_id = session_id};

            auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
                auto* c = static_cast<BridgeCtxStream*>(opaque);
                runanywhere::v1::STTPartialResult partial;
                if (partial_text)
                    partial.set_text(partial_text);
                partial.set_is_final(is_final == RAC_TRUE);
                partial.set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
                partial.set_language(c->language);
                if (is_final == RAC_TRUE) {
                    runanywhere::v1::STTOutput final_output;
                    if (partial_text)
                        final_output.set_text(partial_text);
                    final_output.set_language(c->language);
                    rac::stt::dispatch_stt_stream_event(
                        c->handle, runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL, &partial,
                        &final_output, /*error_message=*/nullptr, /*error_code=*/0, c->session_id);
                } else {
                    rac::stt::dispatch_stt_stream_event(
                        c->handle, runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL, &partial,
                        /*final_output=*/nullptr, /*error_message=*/nullptr,
                        /*error_code=*/0, c->session_id);
                }
            };

            rac_result_t feed_rc = rac_stt_component_stream_feed_audio_chunk(
                component_handle, backend_stream_handle, samples, count, bridge, &ctx);
            if (feed_rc != RAC_SUCCESS) {
                rac::stt::dispatch_stt_stream_event(
                    component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
                    /*partial=*/nullptr, /*final_output=*/nullptr, "STT streaming chunk failed",
                    feed_rc, session_id);
            }
            return feed_rc;
        }
    }

    // Legacy fallback: backend doesn't expose per-session streams. Forward
    // the chunk through the existing transcribe_stream path; Sherpa will
    // pay the per-chunk init cost here (pre-fix behavior) for
    // backends that haven't migrated yet.

    // Bridge struct: forwards per-chunk transcribe_stream callbacks to the
    // proto-byte dispatch. We capture the language code by value so the
    // STTPartialResult / STTOutput payloads receive a stable language enum.
    struct BridgeCtx {
        rac_handle_t handle;
        runanywhere::v1::STTLanguage language;
        size_t audio_size;
        uint64_t session_id;
    } ctx{.handle = component_handle,
          .language = stt_language_from_code(options.language),
          .audio_size = audio_size,
          .session_id = session_id};

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
            rac::stt::dispatch_stt_stream_event(
                c->handle, runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL, &partial, &final_output,
                /*error_message=*/nullptr,
                /*error_code=*/0, c->session_id);
        } else {
            rac::stt::dispatch_stt_stream_event(
                c->handle, runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL, &partial,
                /*final_output=*/nullptr,
                /*error_message=*/nullptr,
                /*error_code=*/0, c->session_id);
        }
    };

    rac_result_t rc = rac_stt_component_transcribe_stream(component_handle, audio_bytes, audio_size,
                                                          &options, bridge, &ctx);
    if (rc != RAC_SUCCESS) {
        rac::stt::dispatch_stt_stream_event(
            component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
            /*partial=*/nullptr,
            /*final_output=*/nullptr, "STT streaming chunk failed", rc, session_id);
    }
    return rc;
#endif
}

rac_result_t rac_stt_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    // Detach the session's backend handle under the lock, then destroy it
    // outside of g_mu() to avoid holding the lock across a backend cleanup
    // path that may re-enter commons.
    rac_handle_t component_handle = nullptr;
    rac_handle_t backend_stream_handle = nullptr;
    std::string request_id;
    std::string language;
    int32_t sample_rate = 0;
    int64_t started_at_ms = 0;
    uint64_t chunks_fed = 0;
    uint64_t audio_bytes = 0;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        component_handle = it->second.handle;
        backend_stream_handle = it->second.backend_stream_handle;
        it->second.backend_stream_handle = nullptr;
        request_id = it->second.request_id;
        language = it->second.language;
        sample_rate = it->second.sample_rate;
        started_at_ms = it->second.started_at_ms;
        chunks_fed = it->second.chunks_fed;
        audio_bytes = it->second.audio_bytes;
        g_sessions().erase(it);
    }
    if (component_handle && backend_stream_handle) {
        (void)rac_stt_component_stream_destroy(component_handle, backend_stream_handle);
    }

#if defined(RAC_HAVE_PROTOBUF)
    // ONE telemetry summary per streaming session. Per-chunk events are
    // PUBLIC-only (they were producing telemetry rows + an HTTP flush per
    // chunk); this row carries the session aggregates instead.
    if (chunks_fed > 0) {
        const int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                   std::chrono::system_clock::now().time_since_epoch())
                                   .count();
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED);
        if (component_handle) {
            if (const char* model_id = rac_stt_component_get_model_id(component_handle)) {
                voice.set_model_id(model_id);
            }
        }
        voice.set_is_streaming(true);
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_bytes));
        // Session wall-clock duration; chunk count rides on segment-less
        // word_count-free schema via audio size + duration.
        if (started_at_ms > 0 && now_ms > started_at_ms) {
            voice.set_duration_ms(now_ms - started_at_ms);
        }
        if (!language.empty()) {
            voice.set_language(language);
        }
        if (sample_rate > 0) {
            voice.set_sample_rate(sample_rate);
        }
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          request_id.c_str());
    }
#endif
    return RAC_SUCCESS;
}

rac_result_t rac_stt_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    rac_handle_t component_handle = nullptr;
    rac_handle_t backend_stream_handle = nullptr;
    std::string request_id;
    std::string language;
    int32_t sample_rate = 0;
    int64_t started_at_ms = 0;
    uint64_t chunks_fed = 0;
    uint64_t audio_bytes = 0;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end())
            return RAC_ERROR_INVALID_ARGUMENT;
        it->second.is_cancelled.store(true, std::memory_order_relaxed);
        component_handle = it->second.handle;
        backend_stream_handle = it->second.backend_stream_handle;
        it->second.backend_stream_handle = nullptr;
        request_id = it->second.request_id;
        language = it->second.language;
        sample_rate = it->second.sample_rate;
        started_at_ms = it->second.started_at_ms;
        chunks_fed = it->second.chunks_fed;
        audio_bytes = it->second.audio_bytes;
        g_sessions().erase(it);
    }
    if (component_handle && backend_stream_handle) {
        (void)rac_stt_component_stream_destroy(component_handle, backend_stream_handle);
    }

#if defined(RAC_HAVE_PROTOBUF)
    // ONE telemetry summary per streaming session — mirror stop_proto, but mark
    // the session FAILED. The Kotlin streaming path calls cancel (not stop) on
    // cancellation/feed errors, so this is the only summary those sessions get.
    if (chunks_fed > 0) {
        const int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                   std::chrono::system_clock::now().time_since_epoch())
                                   .count();
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED);
        if (component_handle) {
            if (const char* model_id = rac_stt_component_get_model_id(component_handle)) {
                voice.set_model_id(model_id);
            }
        }
        voice.set_is_streaming(true);
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_bytes));
        if (started_at_ms > 0 && now_ms > started_at_ms) {
            voice.set_duration_ms(now_ms - started_at_ms);
        }
        if (!language.empty()) {
            voice.set_language(language);
        }
        if (sample_rate > 0) {
            voice.set_sample_rate(sample_rate);
        }
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          request_id.c_str());
    }
#endif
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
void dispatch_stt_stream_event(rac_handle_t handle, runanywhere::v1::STTStreamEventKind kind,
                               const runanywhere::v1::STTPartialResult* partial,
                               const runanywhere::v1::STTOutput* final_output,
                               const char* error_message, int error_code, uint64_t session_id) {
    // Hold the InFlightGuard across the whole
    // dispatch so rac_stt_proto_quiesce() can spin-wait on the counter
    // before destroy threads free user_data.
    rac::stream::InFlightGuard in_flight_guard(g_in_flight);
    rac::stream::CallbackSlot<rac_stt_stream_proto_callback_fn> slot;
    uint64_t seq = 0;
    std::string request_id;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        slot = it->second;
        seq = ++(it->second.seq);
        // Prefer the caller-supplied session_id when known so events stay
        // bound to the producing session even with multiple concurrent
        // sessions on the same component handle. Fall back to the legacy
        // first-active-session-by-handle scan only when no session_id was
        // threaded through (e.g. legacy callbacks emitting handle-only).
        if (session_id != 0) {
            auto sit = g_sessions().find(session_id);
            if (sit != g_sessions().end() && sit->second.handle == handle) {
                request_id = sit->second.request_id;
            }
        }
        if (request_id.empty()) {
            for (const auto& [_, session] : g_sessions()) {
                if (session.handle == handle &&
                    !session.is_cancelled.load(std::memory_order_relaxed)) {
                    request_id = session.request_id;
                    break;
                }
            }
        }
    }

    thread_local runanywhere::v1::STTStreamEvent proto_event;
    thread_local std::vector<uint8_t> scratch;

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
    if (scratch.size() < needed)
        scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("stt", "dispatch_stt_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::stt
#endif  // RAC_HAVE_PROTOBUF
