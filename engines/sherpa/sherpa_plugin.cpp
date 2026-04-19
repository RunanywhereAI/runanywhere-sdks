// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// sherpa-onnx L2 engine plugin — implements transcribe, synthesize, and
// detect_voice primitives via the sherpa-onnx C-API.
//
// The plugin wraps three separate sherpa-onnx state objects:
//   * SherpaOnnxOnlineRecognizer (+ stream) for streaming STT
//   * SherpaOnnxVoiceActivityDetector         for VAD + barge-in
//   * SherpaOnnxOfflineTts                    for one-shot TTS
//
// Model paths for each primitive come from ra_model_spec_t::model_path.
// For STT/TTS/VAD the caller passes a directory or file-prefix and the
// plugin resolves the individual files relative to it. The path layout
// matches the sherpa-onnx upstream examples.

#include <array>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "ra_plugin.h"
#include "ra_primitives.h"
#include "sherpa-onnx/c-api/c-api.h"

namespace {

// ---------------------------------------------------------------------------
// Path resolution helpers
// ---------------------------------------------------------------------------
//
// Sherpa models ship as a directory of files. We accept:
//   * a directory path        → resolve standard filenames inside
//   * an explicit file path   → use directly (for single-file configs)
//
// Env-var overrides let frontends pick specific sub-files without threading
// a rich spec struct through the C ABI. Safe because the lookups are only
// used at session-create time.
std::string join_path(const std::string& dir, const char* name) {
    if (dir.empty()) return {};
    std::filesystem::path p(dir);
    p /= name;
    return p.string();
}

std::string resolve_or(const std::string& dir, const char* file, const char* envvar) {
    if (const char* v = std::getenv(envvar); v && *v) return v;
    return join_path(dir, file);
}

// ---------------------------------------------------------------------------
// STT session — online recognizer for streaming
// ---------------------------------------------------------------------------
struct SttSession {
    const SherpaOnnxOnlineRecognizer* recognizer = nullptr;
    const SherpaOnnxOnlineStream*     stream     = nullptr;
    ra_transcript_callback_t          cb         = nullptr;
    void*                             cb_ud      = nullptr;
    int32_t                           sample_rate = 16000;
    std::string                       last_partial;
    std::mutex                        mu;  // guards result extraction
};

ra_status_t stt_create(const ra_model_spec_t*     spec,
                        const ra_session_config_t* cfg,
                        ra_stt_session_t**         out) {
    if (!spec || !out || !spec->model_path) return RA_ERR_INVALID_ARGUMENT;

    auto* s = new (std::nothrow) SttSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;

    const std::string dir = spec->model_path;

    // Minimal online transducer config. Frontends pass a directory; the
    // canonical filenames inside are encoder.onnx / decoder.onnx /
    // joiner.onnx / tokens.txt (sherpa-onnx's zipformer-transducer layout).
    const std::string encoder = resolve_or(dir, "encoder.onnx",
                                             "RA_STT_ENCODER");
    const std::string decoder = resolve_or(dir, "decoder.onnx",
                                             "RA_STT_DECODER");
    const std::string joiner  = resolve_or(dir, "joiner.onnx",
                                             "RA_STT_JOINER");
    const std::string tokens  = resolve_or(dir, "tokens.txt",
                                             "RA_STT_TOKENS");

    SherpaOnnxOnlineRecognizerConfig rconf{};
    std::memset(&rconf, 0, sizeof(rconf));
    rconf.feat_config.sample_rate = 16000;
    rconf.feat_config.feature_dim = 80;

    rconf.model_config.transducer.encoder = encoder.c_str();
    rconf.model_config.transducer.decoder = decoder.c_str();
    rconf.model_config.transducer.joiner  = joiner.c_str();
    rconf.model_config.tokens             = tokens.c_str();
    rconf.model_config.num_threads        = cfg && cfg->n_threads > 0
                                              ? cfg->n_threads : 2;
    rconf.model_config.provider           = "cpu";

    rconf.decoding_method          = "greedy_search";
    rconf.max_active_paths         = 4;
    rconf.enable_endpoint          = 1;
    rconf.rule1_min_trailing_silence = 2.4f;
    rconf.rule2_min_trailing_silence = 1.2f;
    rconf.rule3_min_utterance_length = 20.f;

    s->recognizer = ::SherpaOnnxCreateOnlineRecognizer(&rconf);
    if (!s->recognizer) {
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }
    s->stream = ::SherpaOnnxCreateOnlineStream(s->recognizer);
    if (!s->stream) {
        ::SherpaOnnxDestroyOnlineRecognizer(s->recognizer);
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }

    *out = reinterpret_cast<ra_stt_session_t*>(s);
    return RA_OK;
}

void stt_destroy(ra_stt_session_t* handle) {
    auto* s = reinterpret_cast<SttSession*>(handle);
    if (!s) return;
    if (s->stream) ::SherpaOnnxDestroyOnlineStream(s->stream);
    if (s->recognizer) ::SherpaOnnxDestroyOnlineRecognizer(s->recognizer);
    delete s;
}

ra_status_t stt_set_callback(ra_stt_session_t* handle,
                              ra_transcript_callback_t cb, void* ud) {
    auto* s = reinterpret_cast<SttSession*>(handle);
    if (!s) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lk(s->mu);
    s->cb    = cb;
    s->cb_ud = ud;
    return RA_OK;
}

// Drain any results ready for the current stream. Emits partials while
// the recognizer is producing tokens, then a final transcript when an
// endpoint is detected. Called on every feed_audio and on flush.
void stt_emit_ready(SttSession* s) {
    if (!s->recognizer || !s->stream) return;
    while (::SherpaOnnxIsOnlineStreamReady(s->recognizer, s->stream)) {
        ::SherpaOnnxDecodeOnlineStream(s->recognizer, s->stream);
    }
    const auto* res = ::SherpaOnnxGetOnlineStreamResult(s->recognizer,
                                                         s->stream);
    const char* text = res ? res->text : nullptr;

    const bool is_endpoint = ::SherpaOnnxOnlineStreamIsEndpoint(
        s->recognizer, s->stream) != 0;

    if (text && *text) {
        std::string current(text);
        if (current != s->last_partial) {
            s->last_partial = current;
            if (s->cb) {
                ra_transcript_chunk_t chunk{};
                chunk.text          = s->last_partial.c_str();
                chunk.is_partial    = is_endpoint ? 0 : 1;
                chunk.confidence    = 1.f;  // sherpa doesn't expose per-chunk
                chunk.audio_start_us = 0;
                chunk.audio_end_us   = 0;
                s->cb(&chunk, s->cb_ud);
            }
        }
    }

    if (is_endpoint) {
        // Commit the endpoint and reset for the next utterance.
        ::SherpaOnnxOnlineStreamReset(s->recognizer, s->stream);
        s->last_partial.clear();
    }
    if (res) ::SherpaOnnxDestroyOnlineRecognizerResult(res);
}

ra_status_t stt_feed_audio(ra_stt_session_t* handle,
                            const float* pcm, int32_t n, int32_t sr) {
    auto* s = reinterpret_cast<SttSession*>(handle);
    if (!s || !s->stream || !pcm || n <= 0) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lk(s->mu);
    ::SherpaOnnxOnlineStreamAcceptWaveform(s->stream,
                                            sr > 0 ? sr : s->sample_rate,
                                            pcm, n);
    stt_emit_ready(s);
    return RA_OK;
}

ra_status_t stt_flush(ra_stt_session_t* handle) {
    auto* s = reinterpret_cast<SttSession*>(handle);
    if (!s || !s->stream) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lk(s->mu);
    ::SherpaOnnxOnlineStreamInputFinished(s->stream);
    stt_emit_ready(s);
    return RA_OK;
}

// ---------------------------------------------------------------------------
// TTS — offline one-shot synthesis (Kokoro / VITS / Matcha layouts supported)
// ---------------------------------------------------------------------------
struct TtsSession {
    const SherpaOnnxOfflineTts* tts = nullptr;
    int32_t sample_rate = 24000;
    int     speaker_id   = 0;
    float   speed        = 1.f;
};

ra_status_t tts_create(const ra_model_spec_t*     spec,
                        const ra_session_config_t* /*cfg*/,
                        ra_tts_session_t**         out) {
    if (!spec || !out || !spec->model_path) return RA_ERR_INVALID_ARGUMENT;

    auto* s = new (std::nothrow) TtsSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;

    const std::string dir = spec->model_path;

    SherpaOnnxOfflineTtsConfig c{};
    std::memset(&c, 0, sizeof(c));

    // VITS is the most common sherpa-onnx TTS layout, so that's the default
    // path. Frontends can override any individual file via env var.
    const std::string vits_model = resolve_or(dir, "model.onnx",  "RA_TTS_MODEL");
    const std::string tokens     = resolve_or(dir, "tokens.txt",  "RA_TTS_TOKENS");
    const std::string lexicon    = resolve_or(dir, "lexicon.txt", "RA_TTS_LEXICON");
    const std::string data_dir   = resolve_or(dir, "espeak-ng-data",
                                                "RA_TTS_DATA_DIR");

    c.model.vits.model   = vits_model.c_str();
    c.model.vits.tokens  = tokens.c_str();
    c.model.vits.lexicon = lexicon.c_str();
    c.model.vits.data_dir = data_dir.c_str();
    c.model.vits.noise_scale    = 0.667f;
    c.model.vits.noise_scale_w  = 0.8f;
    c.model.vits.length_scale   = 1.f;
    c.model.num_threads = 1;
    c.model.provider    = "cpu";
    c.rule_fsts  = "";
    c.max_num_sentences = 100;

    s->tts = ::SherpaOnnxCreateOfflineTts(&c);
    if (!s->tts) {
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }
    s->sample_rate = ::SherpaOnnxOfflineTtsSampleRate(s->tts);
    *out = reinterpret_cast<ra_tts_session_t*>(s);
    return RA_OK;
}

void tts_destroy(ra_tts_session_t* handle) {
    auto* s = reinterpret_cast<TtsSession*>(handle);
    if (!s) return;
    if (s->tts) ::SherpaOnnxDestroyOfflineTts(s->tts);
    delete s;
}

ra_status_t tts_synthesize(ra_tts_session_t* handle,
                            const char* text,
                            float* out_pcm, int32_t max,
                            int32_t* written, int32_t* sr) {
    auto* s = reinterpret_cast<TtsSession*>(handle);
    if (!s || !s->tts || !text || !out_pcm || !written || max <= 0) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    // Use the non-deprecated GenerateWithConfig API. The simpler (sid,
    // speed) variant was marked @deprecated in v1.12.35+.
    SherpaOnnxGenerationConfig gen{};
    gen.silence_scale        = 1.f;
    gen.speed                = s->speed;
    gen.sid                  = s->speaker_id;
    gen.reference_audio      = nullptr;
    gen.reference_audio_len  = 0;
    gen.reference_sample_rate = 0;
    const auto* audio = ::SherpaOnnxOfflineTtsGenerateWithConfig(
        s->tts, text, &gen,
        /*callback=*/nullptr, /*arg=*/nullptr);
    if (!audio) return RA_ERR_INTERNAL;

    if (sr) *sr = s->sample_rate;

    const int32_t n = audio->n > max ? max : audio->n;
    std::memcpy(out_pcm, audio->samples,
                sizeof(float) * static_cast<std::size_t>(n));
    *written = n;
    ::SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    return RA_OK;
}

ra_status_t tts_cancel(ra_tts_session_t* /*handle*/) {
    // sherpa-onnx offline TTS runs to completion on the caller thread;
    // cancel is a no-op. When we move to streaming TTS (Kokoro) this
    // will flip a stop flag checked inside the progress callback.
    return RA_OK;
}

// ---------------------------------------------------------------------------
// VAD — silero-vad wrapper
// ---------------------------------------------------------------------------
struct VadSession {
    const SherpaOnnxVoiceActivityDetector* vad = nullptr;
    ra_vad_callback_t cb    = nullptr;
    void*             cb_ud = nullptr;
    bool              in_speech = false;
    int32_t           sample_rate = 16000;
    std::mutex        mu;
};

ra_status_t vad_create(const ra_model_spec_t*     spec,
                        const ra_session_config_t* /*cfg*/,
                        ra_vad_session_t**         out) {
    if (!spec || !out || !spec->model_path) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) VadSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;

    SherpaOnnxVadModelConfig c{};
    std::memset(&c, 0, sizeof(c));
    c.silero_vad.model              = spec->model_path;
    c.silero_vad.threshold          = 0.5f;
    c.silero_vad.min_silence_duration = 0.25f;
    c.silero_vad.min_speech_duration  = 0.25f;
    c.silero_vad.window_size          = 512;
    c.sample_rate  = s->sample_rate;
    c.num_threads  = 1;
    c.provider     = "cpu";

    s->vad = ::SherpaOnnxCreateVoiceActivityDetector(&c, 20.f);
    if (!s->vad) {
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }
    *out = reinterpret_cast<ra_vad_session_t*>(s);
    return RA_OK;
}

void vad_destroy(ra_vad_session_t* handle) {
    auto* s = reinterpret_cast<VadSession*>(handle);
    if (!s) return;
    if (s->vad) ::SherpaOnnxDestroyVoiceActivityDetector(s->vad);
    delete s;
}

ra_status_t vad_feed_audio(ra_vad_session_t* handle,
                            const float* pcm, int32_t n, int32_t /*sr*/) {
    auto* s = reinterpret_cast<VadSession*>(handle);
    if (!s || !s->vad || !pcm || n <= 0) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lk(s->mu);

    ::SherpaOnnxVoiceActivityDetectorAcceptWaveform(s->vad, pcm, n);

    // Translate sherpa's booleans into RA VAD events.
    //   speech starts  → RA_VAD_EVENT_VOICE_START + BARGE_IN (upper layer
    //                     decides whether it's a barge-in vs a fresh
    //                     utterance based on playback state).
    //   speech ends    → RA_VAD_EVENT_VOICE_END_OF_UTTERANCE
    //   no segments    → silence
    const bool now_detected = ::SherpaOnnxVoiceActivityDetectorDetected(s->vad) != 0;
    if (now_detected && !s->in_speech) {
        s->in_speech = true;
        if (s->cb) {
            ra_vad_event_t ev{};
            ev.type            = RA_VAD_EVENT_VOICE_START;
            ev.frame_offset_us = 0;
            ev.energy          = 0.f;
            s->cb(&ev, s->cb_ud);

            // Also emit a BARGE_IN: the voice agent's on_barge_in wires
            // this to the transactional cancel boundary. The upper layer
            // can ignore it when no generation is in flight.
            ra_vad_event_t bev{};
            bev.type            = RA_VAD_EVENT_BARGE_IN;
            bev.frame_offset_us = 0;
            bev.energy          = 0.f;
            s->cb(&bev, s->cb_ud);
        }
    } else if (!now_detected && s->in_speech) {
        // Drain any completed segments before signalling end-of-utterance.
        while (::SherpaOnnxVoiceActivityDetectorEmpty(s->vad) == 0) {
            const auto* seg = ::SherpaOnnxVoiceActivityDetectorFront(s->vad);
            if (seg) ::SherpaOnnxDestroySpeechSegment(seg);
            ::SherpaOnnxVoiceActivityDetectorPop(s->vad);
        }
        s->in_speech = false;
        if (s->cb) {
            ra_vad_event_t ev{};
            ev.type            = RA_VAD_EVENT_VOICE_END_OF_UTTERANCE;
            ev.frame_offset_us = 0;
            ev.energy          = 0.f;
            s->cb(&ev, s->cb_ud);
        }
    }
    return RA_OK;
}

ra_status_t vad_set_callback(ra_vad_session_t* handle,
                              ra_vad_callback_t cb, void* ud) {
    auto* s = reinterpret_cast<VadSession*>(handle);
    if (!s) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lk(s->mu);
    s->cb    = cb;
    s->cb_ud = ud;
    return RA_OK;
}

// ---------------------------------------------------------------------------
// Wake-word — keyword spotter
// ---------------------------------------------------------------------------
struct WwSession {
    const SherpaOnnxKeywordSpotter*  spotter = nullptr;
    const SherpaOnnxOnlineStream*    stream  = nullptr;
    std::mutex                        mu;
};

ra_status_t ww_create(const ra_model_spec_t* spec,
                      const char*            keyword,
                      float                  threshold,
                      ra_ww_session_t**      out) {
    if (!spec || !out || !spec->model_path) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) WwSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;

    const std::string dir = spec->model_path;
    const std::string encoder = resolve_or(dir, "encoder.onnx", "RA_WW_ENCODER");
    const std::string decoder = resolve_or(dir, "decoder.onnx", "RA_WW_DECODER");
    const std::string joiner  = resolve_or(dir, "joiner.onnx",  "RA_WW_JOINER");
    const std::string tokens  = resolve_or(dir, "tokens.txt",   "RA_WW_TOKENS");
    const std::string kws     = resolve_or(dir, "keywords.txt", "RA_WW_KEYWORDS");

    SherpaOnnxKeywordSpotterConfig c{};
    std::memset(&c, 0, sizeof(c));
    c.feat_config.sample_rate            = 16000;
    c.feat_config.feature_dim            = 80;
    c.model_config.transducer.encoder    = encoder.c_str();
    c.model_config.transducer.decoder    = decoder.c_str();
    c.model_config.transducer.joiner     = joiner.c_str();
    c.model_config.tokens                = tokens.c_str();
    c.model_config.num_threads           = 1;
    c.model_config.provider              = "cpu";
    c.keywords_file                      = kws.c_str();
    c.keywords_score                     = threshold > 0.f ? threshold : 1.f;
    c.keywords_threshold                 = threshold > 0.f ? threshold : 0.25f;
    c.max_active_paths                   = 4;
    c.num_trailing_blanks                = 1;

    (void)keyword;  // per-session override not yet plumbed into sherpa C API

    s->spotter = ::SherpaOnnxCreateKeywordSpotter(&c);
    if (!s->spotter) {
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }
    s->stream = ::SherpaOnnxCreateKeywordStream(s->spotter);
    if (!s->stream) {
        ::SherpaOnnxDestroyKeywordSpotter(s->spotter);
        delete s;
        return RA_ERR_MODEL_LOAD_FAILED;
    }
    *out = reinterpret_cast<ra_ww_session_t*>(s);
    return RA_OK;
}

void ww_destroy(ra_ww_session_t* handle) {
    auto* s = reinterpret_cast<WwSession*>(handle);
    if (!s) return;
    if (s->stream) ::SherpaOnnxDestroyOnlineStream(s->stream);
    if (s->spotter) ::SherpaOnnxDestroyKeywordSpotter(s->spotter);
    delete s;
}

ra_status_t ww_feed_audio(ra_ww_session_t* handle,
                           const float* pcm, int32_t n, int32_t sr,
                           uint8_t* detected) {
    auto* s = reinterpret_cast<WwSession*>(handle);
    if (!s || !s->stream || !s->spotter || !pcm || !detected || n <= 0) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard<std::mutex> lk(s->mu);
    ::SherpaOnnxOnlineStreamAcceptWaveform(s->stream, sr, pcm, n);
    ::SherpaOnnxDecodeKeywordStream(s->spotter, s->stream);

    const auto* res = ::SherpaOnnxGetKeywordResult(s->spotter, s->stream);
    *detected = (res && res->keyword && *res->keyword) ? 1 : 0;
    if (res) ::SherpaOnnxDestroyKeywordResult(res);
    if (*detected) ::SherpaOnnxResetKeywordStream(s->spotter, s->stream);
    return RA_OK;
}

// ---------------------------------------------------------------------------
// Plugin metadata
// ---------------------------------------------------------------------------
constexpr std::array<ra_primitive_t, 4> kPrimitives = {
    RA_PRIMITIVE_TRANSCRIBE,
    RA_PRIMITIVE_SYNTHESIZE,
    RA_PRIMITIVE_DETECT_VOICE,
    RA_PRIMITIVE_WAKE_WORD,
};
constexpr std::array<ra_model_format_t, 1> kFormats  = { RA_FORMAT_ONNX };
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes = { RA_RUNTIME_ORT };

}  // namespace

RA_PLUGIN_ENTRY_DECL(sherpa) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "sherpa";
    out_vtable->metadata.version           = "0.2.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();

    out_vtable->stt_create        = &stt_create;
    out_vtable->stt_destroy       = &stt_destroy;
    out_vtable->stt_feed_audio    = &stt_feed_audio;
    out_vtable->stt_flush         = &stt_flush;
    out_vtable->stt_set_callback  = &stt_set_callback;

    out_vtable->tts_create        = &tts_create;
    out_vtable->tts_destroy       = &tts_destroy;
    out_vtable->tts_synthesize    = &tts_synthesize;
    out_vtable->tts_cancel        = &tts_cancel;

    out_vtable->vad_create        = &vad_create;
    out_vtable->vad_destroy       = &vad_destroy;
    out_vtable->vad_feed_audio    = &vad_feed_audio;
    out_vtable->vad_set_callback  = &vad_set_callback;

    out_vtable->ww_create         = &ww_create;
    out_vtable->ww_destroy        = &ww_destroy;
    out_vtable->ww_feed_audio     = &ww_feed_audio;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(sherpa)
