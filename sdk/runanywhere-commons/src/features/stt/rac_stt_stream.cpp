/**
 * @file rac_stt_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte STT stream ABI
 *        declared in `rac_stt_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids that the
 *     lifecycle manager owns. start() seeds a session, stop()/cancel()
 *     tear it down. Component load/unload/reset/destroy closes a private
 *     start gate, cancels every session for that handle, and drains provider
 *     work before mutating the model lifecycle.
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

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "features/stt/rac_stt_stream_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "stt_options.pb.h"

#include "infrastructure/events/sdk_event_publish.h"
#endif

namespace {

// Lift the voice_agent in_flight quiesce pattern
// to the STT proto-byte dispatcher. See rac_llm_stream.cpp and
// rac_vlm_proto_abi.cpp for the canonical reference; this guards
// dispatch_stt_stream_event so destroy/teardown can spin-wait until any
// in-flight slot.fn() returns before freeing user_data.
std::atomic<int> g_in_flight{0};
thread_local int g_dispatch_depth = 0;

enum class SessionTermination {
    kActive,
    kStop,
    kCancel,
};

// Feed/provider calls and callback dispatches outlive the short critical
// sections protecting g_sessions(). Keep their lifetime state separately so a
// stop/cancel can close the session, wait for external callers, or defer
// cleanup when invoked re-entrantly from the session's own callback.
struct StreamOperationState {
    std::mutex mutex;
    std::condition_variable cv;
    SessionTermination termination = SessionTermination::kActive;
    bool drop_events = false;
    bool cleanup_deferred = false;
    bool cleanup_claimed = false;
    bool cleanup_finished = false;
    size_t in_flight_feeds = 0;
    size_t in_flight_dispatches = 0;
    rac_handle_t backend_stream_handle = nullptr;
    bool backend_stream_unsupported = false;
};

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
    // The public streaming feed ABI accepts raw signed 16-bit little-endian
    // PCM only. Keep this separate from audio_format because proto-only
    // containers such as OGG/M4A have no corresponding C enum and must never
    // be silently collapsed to PCM.
    bool accepts_raw_pcm_s16le = true;
    bool enable_punctuation = true;
    bool enable_diarization = false;
    int32_t max_speakers = 0;
    bool enable_timestamps = true;
    bool detect_language = false;
    // Per-session backend recognizer handle. Lazily created on the
    // first accepted audio chunk via the new stream_create vtable slot.
    // Backends that don't implement the slot leave this nullptr and
    // rac_stt_stream_feed_audio_proto uses the one-shot per-chunk
    // transcribe_stream engine path.
    std::shared_ptr<StreamOperationState> operations = std::make_shared<StreamOperationState>();
    // Fallback endpointing for engines (QHexRT/Whisper) that expose only
    // one-shot transcription. Feeding each 100 ms mic chunk as a fresh
    // inference produces empty text and an unbounded queue; keep a bounded
    // utterance here and invoke the backend only at an endpoint/final flush.
    std::vector<uint8_t> fallback_frame_accum;
    std::vector<uint8_t> fallback_utterance;
    bool fallback_in_speech = false;
    int fallback_speech_ms = 0;
    int fallback_silence_ms = 0;
    // Session aggregates for the ONE telemetry summary emitted at stop —
    // per-chunk events are PUBLIC-only so a live session does not produce a
    // telemetry row (and an HTTP flush) per chunk.
    int64_t started_at_ms = 0;
    uint64_t chunks_fed = 0;
    uint64_t audio_bytes = 0;
};

// Identifies a stop/cancel invoked from the currently executing callback. Such
// a call cannot synchronously wait for its own dispatch/feed without deadlock;
// the last operation guard owns deferred cleanup instead.
#if defined(RAC_HAVE_PROTOBUF)
thread_local uint64_t g_dispatching_session_id = 0;
thread_local uint64_t g_draining_stop_session_id = 0;

class StopDrainDispatchScope {
   public:
    explicit StopDrainDispatchScope(uint64_t session_id) : previous_(g_draining_stop_session_id) {
        g_draining_stop_session_id = session_id;
    }
    ~StopDrainDispatchScope() { g_draining_stop_session_id = previous_; }

   private:
    uint64_t previous_;
};
#endif

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

struct StreamComponentState {
    bool accepting_sessions = true;
    uint64_t owner_id = 0;
    uint64_t stream_epoch = 0;
};

std::unordered_map<rac_handle_t, StreamComponentState>& g_stream_components() {
    static std::unordered_map<rac_handle_t, StreamComponentState> m;
    return m;
}

uint64_t& g_next_component_generation() {
    static uint64_t generation = 0;
    return generation;
}

uint64_t next_component_generation_locked() {
    uint64_t& generation = g_next_component_generation();
    ++generation;
    if (generation == 0) {
        ++generation;
    }
    return generation;
}

std::condition_variable& g_stream_component_cv() {
    static std::condition_variable cv;
    return cv;
}

rac::stt::StopFlushAdmissionTestHook& g_stop_flush_admission_test_hook() {
    static rac::stt::StopFlushAdmissionTestHook hook = nullptr;
    return hook;
}

void*& g_stop_flush_admission_test_user_data() {
    static void* user_data = nullptr;
    return user_data;
}

thread_local std::vector<rac_handle_t> g_stream_teardown_stack;

bool current_thread_owns_stream_teardown(rac_handle_t handle) {
    return std::find(g_stream_teardown_stack.begin(), g_stream_teardown_stack.end(), handle) !=
           g_stream_teardown_stack.end();
}

void release_current_thread_stream_teardown(rac_handle_t handle) {
    const auto it =
        std::find(g_stream_teardown_stack.rbegin(), g_stream_teardown_stack.rend(), handle);
    if (it != g_stream_teardown_stack.rend()) {
        g_stream_teardown_stack.erase(std::next(it).base());
    }
}

constexpr int kFallbackFrameMs = 100;
constexpr int kFallbackMinSpeechMs = 300;
constexpr int kFallbackEndSilenceMs = 800;
constexpr int kFallbackMaxUtteranceMs = 15000;
constexpr float kFallbackSpeechRms = 0.01f;

size_t fallback_frame_bytes(const StreamSession& session) {
    const int32_t sample_rate =
        session.sample_rate > 0 ? session.sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;
    return (static_cast<size_t>(sample_rate) * static_cast<size_t>(kFallbackFrameMs) / 1000U) *
           sizeof(int16_t);
}

float fallback_frame_rms(const uint8_t* bytes, size_t size) {
    const size_t count = size / sizeof(int16_t);
    if (!bytes || count == 0)
        return 0.0f;
    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        int16_t raw_sample = 0;
        // The byte accumulator has byte alignment, so read without an
        // unaligned int16_t reinterpret_cast.
        std::memcpy(&raw_sample, bytes + i * sizeof(int16_t), sizeof(raw_sample));
        const double sample = static_cast<double>(raw_sample);
        sum += sample * sample;
    }
    return static_cast<float>(std::sqrt(sum / static_cast<double>(count)) / 32767.0);
}

void reset_fallback_utterance(StreamSession& session) {
    session.fallback_utterance.clear();
    session.fallback_in_speech = false;
    session.fallback_speech_ms = 0;
    session.fallback_silence_ms = 0;
}

bool feed_fallback_utterance(StreamSession& session, const uint8_t* audio_bytes, size_t audio_size,
                             bool is_final, std::string* out_audio) {
    const size_t frame_bytes = fallback_frame_bytes(session);
    const size_t pre_roll_bytes = frame_bytes * 3U;
    if (frame_bytes == 0) {
        return false;
    }
    if (audio_bytes && audio_size > 0) {
        session.fallback_frame_accum.insert(session.fallback_frame_accum.end(), audio_bytes,
                                            audio_bytes + audio_size);
    }

    while (session.fallback_frame_accum.size() >= frame_bytes) {
        const uint8_t* frame = session.fallback_frame_accum.data();
        const bool is_speech = fallback_frame_rms(frame, frame_bytes) >= kFallbackSpeechRms;

        session.fallback_utterance.insert(session.fallback_utterance.end(), frame,
                                          frame + frame_bytes);
        session.fallback_frame_accum.erase(session.fallback_frame_accum.begin(),
                                           session.fallback_frame_accum.begin() +
                                               static_cast<std::ptrdiff_t>(frame_bytes));

        if (!session.fallback_in_speech) {
            if (session.fallback_utterance.size() > pre_roll_bytes) {
                const size_t excess = session.fallback_utterance.size() - pre_roll_bytes;
                session.fallback_utterance.erase(session.fallback_utterance.begin(),
                                                 session.fallback_utterance.begin() +
                                                     static_cast<std::ptrdiff_t>(excess));
            }
            if (is_speech) {
                session.fallback_in_speech = true;
                session.fallback_speech_ms = kFallbackFrameMs;
                session.fallback_silence_ms = 0;
            }
            continue;
        }

        if (is_speech) {
            session.fallback_speech_ms += kFallbackFrameMs;
            session.fallback_silence_ms = 0;
        } else {
            session.fallback_silence_ms += kFallbackFrameMs;
        }

        const int utterance_ms = static_cast<int>(
            session.fallback_utterance.size() * 1000 /
            (static_cast<size_t>(session.sample_rate > 0 ? session.sample_rate
                                                         : RAC_STT_DEFAULT_SAMPLE_RATE) *
             sizeof(int16_t)));
        if (session.fallback_silence_ms >= kFallbackEndSilenceMs ||
            utterance_ms >= kFallbackMaxUtteranceMs) {
            if (session.fallback_speech_ms >= kFallbackMinSpeechMs) {
                out_audio->assign(reinterpret_cast<const char*>(session.fallback_utterance.data()),
                                  session.fallback_utterance.size());
                reset_fallback_utterance(session);
                // Do not retain mic frames captured behind an expensive
                // one-shot inference; they are stale by the time it returns.
                session.fallback_frame_accum.clear();
                return true;
            }
            reset_fallback_utterance(session);
        }
    }

    if (is_final) {
        if (!session.fallback_frame_accum.empty()) {
            session.fallback_utterance.insert(session.fallback_utterance.end(),
                                              session.fallback_frame_accum.begin(),
                                              session.fallback_frame_accum.end());
            session.fallback_frame_accum.clear();
        }
        if (session.fallback_in_speech && session.fallback_speech_ms >= kFallbackMinSpeechMs &&
            !session.fallback_utterance.empty()) {
            out_audio->assign(reinterpret_cast<const char*>(session.fallback_utterance.data()),
                              session.fallback_utterance.size());
            reset_fallback_utterance(session);
            return true;
        }
        reset_fallback_utterance(session);
    }
    return false;
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

namespace {

rac_result_t transcribe_fallback_utterance(rac_handle_t component_handle, uint64_t session_id,
                                           const std::string& audio,
                                           const rac_stt_options_t& options) {
    if (!component_handle || audio.empty()) {
        return RAC_SUCCESS;
    }

    struct BridgeCtx {
        rac_handle_t handle;
        runanywhere::v1::STTLanguage language;
        uint64_t session_id;
    } ctx{.handle = component_handle,
          .language = stt_language_from_code(options.language),
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
                /*error_message=*/nullptr, /*error_code=*/0, c->session_id);
        } else {
            rac::stt::dispatch_stt_stream_event(
                c->handle, runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL, &partial,
                /*final_output=*/nullptr, /*error_message=*/nullptr, /*error_code=*/0,
                c->session_id);
        }
    };

    const rac_result_t rc = rac_stt_component_transcribe_stream(
        component_handle, audio.data(), audio.size(), &options, bridge, &ctx);
    if (rc != RAC_SUCCESS) {
        rac::stt::dispatch_stt_stream_event(component_handle,
                                            runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
                                            /*partial=*/nullptr, /*final_output=*/nullptr,
                                            "STT streaming utterance failed", rc, session_id);
    }
    return rc;
}

struct SessionCleanupSnapshot {
    rac_handle_t component_handle = nullptr;
    rac_handle_t backend_stream_handle = nullptr;
    std::string request_id;
    std::string language;
    int32_t sample_rate = 0;
    rac_audio_format_enum_t audio_format = RAC_AUDIO_FORMAT_PCM;
    bool detect_language = false;
    bool enable_punctuation = true;
    bool enable_diarization = false;
    int32_t max_speakers = 0;
    bool enable_timestamps = true;
    int64_t started_at_ms = 0;
    uint64_t chunks_fed = 0;
    uint64_t audio_bytes = 0;
    std::string final_utterance;
};

bool operations_quiescent(const StreamOperationState& state) {
    return state.in_flight_feeds == 0 && state.in_flight_dispatches == 0;
}

void publish_session_summary(const SessionCleanupSnapshot& snapshot,
                             SessionTermination termination) {
    if (snapshot.chunks_fed == 0) {
        return;
    }
    const int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                               std::chrono::system_clock::now().time_since_epoch())
                               .count();
    runanywhere::v1::VoiceLifecycleEvent voice;
    voice.set_kind(termination == SessionTermination::kCancel
                       ? runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED
                       : runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED);
    if (snapshot.component_handle) {
        if (const char* model_id = rac_stt_component_get_model_id(snapshot.component_handle)) {
            voice.set_model_id(model_id);
        }
    }
    voice.set_is_streaming(true);
    voice.set_audio_size_bytes(static_cast<int32_t>(snapshot.audio_bytes));
    if (snapshot.started_at_ms > 0 && now_ms > snapshot.started_at_ms) {
        voice.set_duration_ms(now_ms - snapshot.started_at_ms);
    }
    if (!snapshot.language.empty()) {
        voice.set_language(snapshot.language);
    }
    if (snapshot.sample_rate > 0) {
        voice.set_sample_rate(snapshot.sample_rate);
    }
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                      runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                      snapshot.request_id.c_str());
}

// Called only by the thread that atomically claimed cleanup after all feeds and
// callback dispatches quiesced. A normal stop may flush the fallback utterance
// while the session remains addressable; re-entrant stop/cancel cleanup cannot
// emit after the initiating callback returns, so it skips that optional flush.
rac_result_t finalize_terminated_session(uint64_t session_id,
                                         const std::shared_ptr<StreamOperationState>& state,
                                         bool allow_stop_flush) {
    SessionTermination termination = SessionTermination::kCancel;
    bool backend_stream_unsupported = false;
    {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        termination = state->termination;
        backend_stream_unsupported = state->backend_stream_unsupported;
    }

    SessionCleanupSnapshot snapshot;
    rac::stt::StopFlushAdmissionTestHook stop_flush_hook = nullptr;
    void* stop_flush_hook_user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it != g_sessions().end() && it->second.operations.get() == state.get()) {
            StreamSession& session = it->second;
            snapshot.component_handle = session.handle;
            snapshot.request_id = session.request_id;
            snapshot.language = session.language;
            snapshot.sample_rate = session.sample_rate;
            snapshot.audio_format = session.audio_format;
            snapshot.detect_language = session.detect_language;
            snapshot.enable_punctuation = session.enable_punctuation;
            snapshot.enable_diarization = session.enable_diarization;
            snapshot.max_speakers = session.max_speakers;
            snapshot.enable_timestamps = session.enable_timestamps;
            snapshot.started_at_ms = session.started_at_ms;
            snapshot.chunks_fed = session.chunks_fed;
            snapshot.audio_bytes = session.audio_bytes;
            if (allow_stop_flush && termination == SessionTermination::kStop &&
                backend_stream_unsupported) {
                (void)feed_fallback_utterance(session, nullptr, 0, true, &snapshot.final_utterance);
            }
        }
        if (!snapshot.final_utterance.empty()) {
            stop_flush_hook = g_stop_flush_admission_test_hook();
            stop_flush_hook_user_data = g_stop_flush_admission_test_user_data();
        }
    }

    {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        snapshot.backend_stream_handle = state->backend_stream_handle;
        state->backend_stream_handle = nullptr;
    }

    if (stop_flush_hook) {
        stop_flush_hook(session_id, stop_flush_hook_user_data);
    }

    // A concurrent cancel that wins before this admission drops the pending
    // fallback utterance. Once admitted, the provider call is treated like any
    // other already-accepted work and cancellation waits for it to drain.
    bool run_stop_flush = false;
    if (!snapshot.final_utterance.empty()) {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        if (state->termination == SessionTermination::kStop && !state->drop_events) {
            run_stop_flush = true;
        } else {
            snapshot.final_utterance.clear();
        }
    }

    rac_result_t flush_rc = RAC_SUCCESS;
    if (run_stop_flush) {
        rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
        options.language = snapshot.language.empty() ? nullptr : snapshot.language.c_str();
        options.detect_language = snapshot.detect_language ? RAC_TRUE : RAC_FALSE;
        options.enable_punctuation = snapshot.enable_punctuation ? RAC_TRUE : RAC_FALSE;
        options.enable_diarization = snapshot.enable_diarization ? RAC_TRUE : RAC_FALSE;
        options.max_speakers = snapshot.max_speakers;
        options.enable_timestamps = snapshot.enable_timestamps ? RAC_TRUE : RAC_FALSE;
        options.sample_rate = snapshot.sample_rate;
        options.audio_format = snapshot.audio_format;
        StopDrainDispatchScope drain_scope(session_id);
        flush_rc = transcribe_fallback_utterance(snapshot.component_handle, session_id,
                                                 snapshot.final_utterance, options);
    }

    // Close the dispatch gate before erasing the session or destroying its
    // provider handle. An explicit session id that is missing/closed is always
    // dropped by dispatch_stt_stream_event below.
    {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        state->drop_events = true;
        termination = state->termination;
    }
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it != g_sessions().end() && it->second.operations.get() == state.get()) {
            g_sessions().erase(it);
        }
    }
    if (snapshot.component_handle && snapshot.backend_stream_handle) {
        (void)rac_stt_component_stream_destroy(snapshot.component_handle,
                                               snapshot.backend_stream_handle);
    }
    publish_session_summary(snapshot, termination);

    {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        state->cleanup_finished = true;
    }
    state->cv.notify_all();
    return termination == SessionTermination::kCancel ? RAC_SUCCESS : flush_rc;
}

void release_session_operation(uint64_t session_id,
                               const std::shared_ptr<StreamOperationState>& state, bool feed) {
    bool finalize_deferred = false;
    {
        std::lock_guard<std::mutex> operation_lock(state->mutex);
        size_t& count = feed ? state->in_flight_feeds : state->in_flight_dispatches;
        if (count > 0) {
            --count;
        }
        if (operations_quiescent(*state)) {
            state->cv.notify_all();
            if (state->cleanup_deferred && !state->cleanup_claimed) {
                state->cleanup_claimed = true;
                finalize_deferred = true;
            }
        }
    }
    if (finalize_deferred) {
        (void)finalize_terminated_session(session_id, state, /*allow_stop_flush=*/false);
    }
}

class FeedOperationGuard {
   public:
    FeedOperationGuard(uint64_t session_id, std::shared_ptr<StreamOperationState> state)
        : session_id_(session_id), state_(std::move(state)) {}
    ~FeedOperationGuard() {
        if (state_) {
            release_session_operation(session_id_, state_, /*feed=*/true);
        }
    }
    FeedOperationGuard(const FeedOperationGuard&) = delete;
    FeedOperationGuard& operator=(const FeedOperationGuard&) = delete;

   private:
    uint64_t session_id_;
    std::shared_ptr<StreamOperationState> state_;
};

class DispatchOperationGuard {
   public:
    DispatchOperationGuard(uint64_t session_id, std::shared_ptr<StreamOperationState> state)
        : session_id_(session_id), state_(std::move(state)) {}
    ~DispatchOperationGuard() {
        if (state_) {
            release_session_operation(session_id_, state_, /*feed=*/false);
        }
    }
    DispatchOperationGuard(const DispatchOperationGuard&) = delete;
    DispatchOperationGuard& operator=(const DispatchOperationGuard&) = delete;

   private:
    uint64_t session_id_;
    std::shared_ptr<StreamOperationState> state_;
};

class DispatchSessionScope {
   public:
    explicit DispatchSessionScope(uint64_t session_id) : previous_(g_dispatching_session_id) {
        g_dispatching_session_id = session_id;
    }
    ~DispatchSessionScope() { g_dispatching_session_id = previous_; }

   private:
    uint64_t previous_;
};

class DispatchDepthScope {
   public:
    DispatchDepthScope() { ++g_dispatch_depth; }
    ~DispatchDepthScope() { --g_dispatch_depth; }

    DispatchDepthScope(const DispatchDepthScope&) = delete;
    DispatchDepthScope& operator=(const DispatchDepthScope&) = delete;
};

rac_result_t terminate_stream_session(uint64_t session_id, SessionTermination requested) {
    std::shared_ptr<StreamOperationState> state;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end()) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        it->second.is_cancelled.store(true, std::memory_order_release);
        state = it->second.operations;
    }

    const bool reentrant = g_dispatching_session_id == session_id;
    {
        std::unique_lock<std::mutex> operation_lock(state->mutex);
        if (state->termination == SessionTermination::kActive ||
            requested == SessionTermination::kCancel) {
            state->termination = requested;
        }
        if (requested == SessionTermination::kCancel || reentrant) {
            // Cancellation is fail-closed immediately. A re-entrant stop must
            // also suppress anything after its current callback because it
            // cannot wait for itself before returning.
            state->drop_events = true;
        }

        if (reentrant) {
            if (!state->cleanup_claimed) {
                state->cleanup_deferred = true;
            }
            return RAC_SUCCESS;
        }

        state->cv.wait(operation_lock,
                       [&] { return operations_quiescent(*state) || state->cleanup_claimed; });
        if (state->cleanup_claimed) {
            state->cv.wait(operation_lock, [&] { return state->cleanup_finished; });
            return RAC_SUCCESS;
        }
        state->cleanup_claimed = true;
    }

    const bool allow_stop_flush = requested == SessionTermination::kStop;
    return finalize_terminated_session(session_id, state, allow_stop_flush);
}

}  // namespace
#endif

namespace rac::stt {

void register_stream_component(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_mu());
    const uint64_t owner_id = next_component_generation_locked();
    g_stream_components()[handle] = StreamComponentState{
        .accepting_sessions = true,
        .owner_id = owner_id,
        .stream_epoch = owner_id,
    };
}

void unregister_stream_component(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_mu());
        g_slots().erase(handle);
        g_stream_components().erase(handle);
    }
    release_current_thread_stream_teardown(handle);
    g_stream_component_cv().notify_all();
}

rac_result_t begin_stream_component_teardown(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (current_thread_owns_stream_teardown(handle)) {
        return RAC_ERROR_SERVICE_BUSY;
    }

#if defined(RAC_HAVE_PROTOBUF)
    std::vector<uint64_t> session_ids;
#endif
    {
        std::unique_lock<std::mutex> lock(g_mu());
        auto component = g_stream_components().find(handle);
        if (component == g_stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        const uint64_t owner_id = component->second.owner_id;
#if defined(RAC_HAVE_PROTOBUF)
        if (g_dispatching_session_id != 0) {
            auto dispatching = g_sessions().find(g_dispatching_session_id);
            if (dispatching != g_sessions().end() && dispatching->second.handle == handle) {
                // A callback cannot synchronously wait for its own feed and
                // dispatch to drain. Refuse the lifecycle mutation instead of
                // deadlocking or tearing the model down beneath that callback.
                return RAC_ERROR_SERVICE_BUSY;
            }
        }
#endif
        g_stream_component_cv().wait(lock, [&] {
            const auto current = g_stream_components().find(handle);
            return current == g_stream_components().end() || current->second.owner_id != owner_id ||
                   current->second.accepting_sessions;
        });
        component = g_stream_components().find(handle);
        if (component == g_stream_components().end() || component->second.owner_id != owner_id) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        component->second.accepting_sessions = false;
        component->second.stream_epoch = next_component_generation_locked();
        g_stream_teardown_stack.push_back(handle);
#if defined(RAC_HAVE_PROTOBUF)
        for (const auto& [session_id, session] : g_sessions()) {
            if (session.handle == handle) {
                session_ids.push_back(session_id);
            }
        }
#endif
    }

#if defined(RAC_HAVE_PROTOBUF)
    for (uint64_t session_id : session_ids) {
        const rac_result_t rc = terminate_stream_session(session_id, SessionTermination::kCancel);
        if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_ARGUMENT) {
            end_stream_component_teardown(handle);
            return rc;
        }
    }
#endif
    return RAC_SUCCESS;
}

void end_stream_component_teardown(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto component = g_stream_components().find(handle);
        if (component != g_stream_components().end()) {
            component->second.accepting_sessions = true;
        }
    }
    release_current_thread_stream_teardown(handle);
    g_stream_component_cv().notify_all();
}

void set_stop_flush_admission_test_hook(StopFlushAdmissionTestHook hook, void* user_data) {
    std::lock_guard<std::mutex> lock(g_mu());
    g_stop_flush_admission_test_hook() = hook;
    g_stop_flush_admission_test_user_data() = user_data;
}

bool stream_session_termination_started_for_testing(uint64_t session_id) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_id;
    return false;
#else
    std::lock_guard<std::mutex> lock(g_mu());
    const auto session = g_sessions().find(session_id);
    if (session == g_sessions().end()) {
        return false;
    }
    std::lock_guard<std::mutex> operation_lock(session->second.operations->mutex);
    return session->second.operations->termination != SessionTermination::kActive;
#endif
}

bool stream_session_cancel_requested_for_testing(uint64_t session_id) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_id;
    return false;
#else
    std::lock_guard<std::mutex> lock(g_mu());
    const auto session = g_sessions().find(session_id);
    if (session == g_sessions().end()) {
        return false;
    }
    std::lock_guard<std::mutex> operation_lock(session->second.operations->mutex);
    return session->second.operations->termination == SessionTermination::kCancel;
#endif
}

bool has_stream_callback_for_testing(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(g_mu());
    const auto slot = g_slots().find(handle);
    return slot != g_slots().end() && slot->second.fn != nullptr;
}

}  // namespace rac::stt

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
        const auto component = g_stream_components().find(handle);
        if (component == g_stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (!component->second.accepting_sessions) {
            return RAC_ERROR_SERVICE_BUSY;
        }
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
    // A callback may unregister itself and quiesce re-entrantly. Its own
    // InFlightGuard cannot retire until that callback returns, so wait for all
    // *other* dispatches rather than spinning forever on the current stack.
    const int current_thread_dispatches = g_dispatch_depth;
    while (g_in_flight.load(std::memory_order_acquire) > current_thread_dispatches) {
        std::this_thread::yield();
    }
}

rac_result_t rac_stt_stream_start_proto(rac_handle_t handle, const uint8_t* options_proto_bytes,
                                        size_t options_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out_session_id = 0;
    if (options_proto_size > 0 && options_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)options_proto_bytes;
    (void)options_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    uint64_t component_owner_id = 0;
    uint64_t component_stream_epoch = 0;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        const auto component = g_stream_components().find(handle);
        if (component == g_stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (!component->second.accepting_sessions) {
            return RAC_ERROR_SERVICE_BUSY;
        }
        component_owner_id = component->second.owner_id;
        component_stream_epoch = component->second.stream_epoch;
    }

    runanywhere::v1::STTOptions parsed;
    if (options_proto_size > 0 &&
        !parsed.ParseFromArray(options_proto_bytes, static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const uint64_t id = g_session_ids.next();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        const auto component = g_stream_components().find(handle);
        if (component == g_stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (component->second.owner_id != component_owner_id) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (!component->second.accepting_sessions ||
            component->second.stream_epoch != component_stream_epoch) {
            return RAC_ERROR_SERVICE_BUSY;
        }
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
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_MP3:
                s.audio_format = RAC_AUDIO_FORMAT_MP3;
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_OPUS:
                s.audio_format = RAC_AUDIO_FORMAT_OPUS;
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_AAC:
                s.audio_format = RAC_AUDIO_FORMAT_AAC;
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_FLAC:
                s.audio_format = RAC_AUDIO_FORMAT_FLAC;
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_OGG:
            case runanywhere::v1::AUDIO_FORMAT_M4A:
                // No C enum equivalents exist. Preserve the public C options
                // default while retaining the proto format as unsupported for
                // raw stream ingestion via the explicit policy flag.
                s.audio_format = RAC_AUDIO_FORMAT_PCM;
                s.accepts_raw_pcm_s16le = false;
                break;
            case runanywhere::v1::AUDIO_FORMAT_PCM:
            case runanywhere::v1::AUDIO_FORMAT_PCM_S16LE:
            case runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED:
                s.audio_format = RAC_AUDIO_FORMAT_PCM;
                s.accepts_raw_pcm_s16le = true;
                break;
            default:
                s.audio_format = RAC_AUDIO_FORMAT_PCM;
                s.accepts_raw_pcm_s16le = false;
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
    bool accepts_raw_pcm_s16le = true;
    std::shared_ptr<StreamOperationState> operation_state;
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
        accepts_raw_pcm_s16le = it->second.accepts_raw_pcm_s16le;
        operation_state = it->second.operations;
        request_id = it->second.request_id;
    }
    if (component_handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (audio_size == 0) {
        return RAC_SUCCESS;
    }
    if (!accepts_raw_pcm_s16le) {
        rac::stt::dispatch_stt_stream_event(
            component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
            /*partial=*/nullptr, /*final_output=*/nullptr,
            "STT stream ingestion requires signed 16-bit little-endian PCM audio",
            RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED, session_id);
        return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED;
    }
    if (audio_size % sizeof(int16_t) != 0) {
        rac::stt::dispatch_stt_stream_event(
            component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
            /*partial=*/nullptr, /*final_output=*/nullptr,
            "STT signed 16-bit PCM input must contain whole samples", RAC_ERROR_INVALID_ARGUMENT,
            session_id);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Own one feed operation before accounting, event emission, provider
    // creation/feed, and fallback mutation. stop/cancel closes this gate before
    // waiting, so a provider handle cannot be destroyed between the snapshot
    // above and its eventual use below.
    {
        std::lock_guard<std::mutex> operation_lock(operation_state->mutex);
        if (operation_state->termination != SessionTermination::kActive) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        ++operation_state->in_flight_feeds;
        backend_stream_handle = operation_state->backend_stream_handle;
        backend_stream_unsupported = operation_state->backend_stream_unsupported;
    }
    FeedOperationGuard feed_guard(session_id, operation_state);
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end() || it->second.operations.get() != operation_state.get()) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        // Aggregate for the one summary telemetry row emitted at stop.
        first_chunk = (it->second.chunks_fed == 0);
        it->second.chunks_fed += 1;
        it->second.audio_bytes += audio_size;
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
                rac_handle_t redundant_stream = nullptr;
                bool cancelled = false;
                {
                    std::lock_guard<std::mutex> operation_lock(operation_state->mutex);
                    cancelled = operation_state->termination == SessionTermination::kCancel;
                    if (cancelled) {
                        redundant_stream = new_stream;
                    } else if (operation_state->backend_stream_handle != nullptr) {
                        // Another concurrent feed may have raced us; keep the
                        // first-in-wins handle and destroy ours if so.
                        redundant_stream = new_stream;
                        backend_stream_handle = operation_state->backend_stream_handle;
                    } else {
                        operation_state->backend_stream_handle = new_stream;
                        backend_stream_handle = new_stream;
                    }
                }
                if (redundant_stream != nullptr) {
                    (void)rac_stt_component_stream_destroy(component_handle, redundant_stream);
                }
                if (cancelled) {
                    return RAC_ERROR_INVALID_ARGUMENT;
                }
            } else if (create_rc == RAC_ERROR_NOT_SUPPORTED) {
                // Backend didn't wire the new slot — remember so subsequent
                // chunks skip the create probe and take the legacy path
                // straight away.
                std::lock_guard<std::mutex> operation_lock(operation_state->mutex);
                if (operation_state->termination == SessionTermination::kCancel) {
                    return RAC_ERROR_INVALID_ARGUMENT;
                }
                operation_state->backend_stream_unsupported = true;
                backend_stream_unsupported = true;
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
            const size_t count = audio_size / sizeof(int16_t);
            std::vector<int16_t> aligned_samples(count);
            std::memcpy(aligned_samples.data(), audio_bytes, audio_size);

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
                component_handle, backend_stream_handle, aligned_samples.data(), count, bridge,
                &ctx);
            if (feed_rc != RAC_SUCCESS) {
                rac::stt::dispatch_stt_stream_event(
                    component_handle, runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR,
                    /*partial=*/nullptr, /*final_output=*/nullptr, "STT streaming chunk failed",
                    feed_rc, session_id);
            }
            return feed_rc;
        }
    }

    // One-shot fallback: buffer cheap 100 ms feeds in commons and invoke the
    // expensive recognizer only after speech + trailing silence closes an
    // utterance. This keeps unsupported QHexRT/Whisper sessions genuinely
    // usable as Live STT without per-frame inference or queue growth.
    std::string utterance;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_sessions().find(session_id);
        if (it == g_sessions().end() || it->second.operations.get() != operation_state.get()) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        if (!feed_fallback_utterance(it->second, audio_bytes, audio_size, false, &utterance)) {
            return RAC_SUCCESS;
        }
    }
    return transcribe_fallback_utterance(component_handle, session_id, utterance, options);
#endif
}

rac_result_t rac_stt_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
#if defined(RAC_HAVE_PROTOBUF)
    return terminate_stream_session(session_id, SessionTermination::kStop);
#else
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t rac_stt_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
#if defined(RAC_HAVE_PROTOBUF)
    return terminate_stream_session(session_id, SessionTermination::kCancel);
#else
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

}  // extern "C"

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::stt {

/**
 * @brief Internal helper invoked by stt_component.cpp's streaming
 *        dispatcher per partial/final result. Serializes one
 *        STTStreamEvent and fires the registered callback.
 *
 * Available only when Protobuf is linked. Non-Protobuf builds expose the
 * backend-facing text callback directly and do not emit SDK proto events.
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
    uint64_t correlated_session_id = session_id;
    std::shared_ptr<StreamOperationState> operation_state;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        // Prefer the caller-supplied session_id when known so events stay
        // bound to the producing session even with multiple concurrent
        // sessions on the same component handle. Fall back to the legacy
        // first-active-session-by-handle scan only when no session_id was
        // threaded through (e.g. legacy callbacks emitting handle-only).
        if (session_id != 0) {
            auto sit = g_sessions().find(session_id);
            if (sit == g_sessions().end() || sit->second.handle != handle) {
                // Never relabel a late explicit-session event onto another
                // session sharing the same component handle.
                return;
            }
            request_id = sit->second.request_id;
            operation_state = sit->second.operations;
        }
        if (session_id == 0) {
            for (const auto& [candidate_id, session] : g_sessions()) {
                if (session.handle == handle &&
                    !session.is_cancelled.load(std::memory_order_relaxed)) {
                    request_id = session.request_id;
                    correlated_session_id = candidate_id;
                    operation_state = session.operations;
                    break;
                }
            }
        }
        if (operation_state) {
            std::lock_guard<std::mutex> operation_lock(operation_state->mutex);
            const bool draining_accepted_feed =
                operation_state->termination == SessionTermination::kStop &&
                operation_state->in_flight_feeds > 0;
            const bool draining_stop_flush =
                operation_state->termination == SessionTermination::kStop &&
                g_draining_stop_session_id == correlated_session_id;
            if (operation_state->drop_events || operation_state->cleanup_finished ||
                (operation_state->termination != SessionTermination::kActive &&
                 !draining_accepted_feed && !draining_stop_flush)) {
                return;
            }
            ++operation_state->in_flight_dispatches;
        }
        slot = it->second;
        seq = ++(it->second.seq);
    }
    DispatchOperationGuard dispatch_guard(correlated_session_id, operation_state);

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
    DispatchSessionScope dispatch_scope(correlated_session_id);
    DispatchDepthScope dispatch_depth_scope;
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::stt
#endif  // RAC_HAVE_PROTOBUF
