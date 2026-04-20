// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// C ABI dispatch layer for STT / TTS / VAD / Embed / WakeWord primitives.
// Mirrors ra_llm_dispatch.cpp for the non-LLM primitive family: each
// ra_X_create picks a plugin via the router, wraps the inner session in
// a DispatchXSession handle that carries the vtable reference, and
// subsequent calls forward through the plugin's vtable.

#include "ra_primitives.h"
#include "ra_plugin.h"

#include "../registry/plugin_registry.h"
#include "../router/engine_router.h"
#include "../router/hardware_profile.h"

#include <memory>
#include <new>

namespace {

ra::core::EngineRouter& router() {
    static ra::core::EngineRouter instance(
        ra::core::PluginRegistry::global(),
        ra::core::HardwareProfile::detect());
    return instance;
}

ra::core::PluginHandleRef select(ra_primitive_t prim, const ra_model_spec_t* spec) {
    ra::core::RouteRequest req;
    req.primitive = prim;
    req.format    = spec ? spec->format : RA_FORMAT_UNKNOWN;
    return router().route(req).plugin;
}

template <typename InnerT>
struct DispatchSession {
    ra::core::PluginHandleRef plugin;
    InnerT*                   inner;
};

using STTDispatch   = DispatchSession<ra_stt_session_t>;
using TTSDispatch   = DispatchSession<ra_tts_session_t>;
using VADDispatch   = DispatchSession<ra_vad_session_t>;
using EmbedDispatch = DispatchSession<ra_embed_session_t>;
using WWDispatch    = DispatchSession<ra_ww_session_t>;

}  // namespace

extern "C" {

// --- STT ----------------------------------------------------------------

ra_status_t ra_stt_create(const ra_model_spec_t*     spec,
                           const ra_session_config_t* cfg,
                           ra_stt_session_t**         out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select(RA_PRIMITIVE_TRANSCRIBE, spec);
    if (!plugin || !plugin->vtable.stt_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_stt_session_t* inner = nullptr;
    const auto rc = plugin->vtable.stt_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;

    auto* w = new (std::nothrow) STTDispatch{plugin, inner};
    if (!w) {
        if (plugin->vtable.stt_destroy) plugin->vtable.stt_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_stt_session_t*>(w);
    return RA_OK;
}

void ra_stt_destroy(ra_stt_session_t* session) {
    auto* w = reinterpret_cast<STTDispatch*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.stt_destroy && w->inner) {
        w->plugin->vtable.stt_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_stt_feed_audio(ra_stt_session_t* session, const float* pcm,
                               int32_t n, int32_t sr) {
    auto* w = reinterpret_cast<STTDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.stt_feed_audio) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.stt_feed_audio(w->inner, pcm, n, sr);
}

ra_status_t ra_stt_flush(ra_stt_session_t* session) {
    auto* w = reinterpret_cast<STTDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.stt_flush) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.stt_flush(w->inner);
}

ra_status_t ra_stt_set_callback(ra_stt_session_t* session,
                                 ra_transcript_callback_t cb, void* ud) {
    auto* w = reinterpret_cast<STTDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.stt_set_callback) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.stt_set_callback(w->inner, cb, ud);
}

// --- TTS ----------------------------------------------------------------

ra_status_t ra_tts_create(const ra_model_spec_t*     spec,
                           const ra_session_config_t* cfg,
                           ra_tts_session_t**         out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select(RA_PRIMITIVE_SYNTHESIZE, spec);
    if (!plugin || !plugin->vtable.tts_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_tts_session_t* inner = nullptr;
    const auto rc = plugin->vtable.tts_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;

    auto* w = new (std::nothrow) TTSDispatch{plugin, inner};
    if (!w) {
        if (plugin->vtable.tts_destroy) plugin->vtable.tts_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_tts_session_t*>(w);
    return RA_OK;
}

void ra_tts_destroy(ra_tts_session_t* session) {
    auto* w = reinterpret_cast<TTSDispatch*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.tts_destroy && w->inner) {
        w->plugin->vtable.tts_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_tts_synthesize(ra_tts_session_t* session, const char* text,
                               float* out_pcm, int32_t max, int32_t* written,
                               int32_t* sr) {
    auto* w = reinterpret_cast<TTSDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.tts_synthesize) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.tts_synthesize(w->inner, text, out_pcm, max, written, sr);
}

ra_status_t ra_tts_cancel(ra_tts_session_t* session) {
    auto* w = reinterpret_cast<TTSDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.tts_cancel) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.tts_cancel(w->inner);
}

// --- VAD ----------------------------------------------------------------

ra_status_t ra_vad_create(const ra_model_spec_t*     spec,
                           const ra_session_config_t* cfg,
                           ra_vad_session_t**         out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select(RA_PRIMITIVE_DETECT_VOICE, spec);
    if (!plugin || !plugin->vtable.vad_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_vad_session_t* inner = nullptr;
    const auto rc = plugin->vtable.vad_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;

    auto* w = new (std::nothrow) VADDispatch{plugin, inner};
    if (!w) {
        if (plugin->vtable.vad_destroy) plugin->vtable.vad_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_vad_session_t*>(w);
    return RA_OK;
}

void ra_vad_destroy(ra_vad_session_t* session) {
    auto* w = reinterpret_cast<VADDispatch*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.vad_destroy && w->inner) {
        w->plugin->vtable.vad_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_vad_feed_audio(ra_vad_session_t* session, const float* pcm,
                               int32_t n, int32_t sr) {
    auto* w = reinterpret_cast<VADDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.vad_feed_audio) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.vad_feed_audio(w->inner, pcm, n, sr);
}

ra_status_t ra_vad_set_callback(ra_vad_session_t* session,
                                 ra_vad_callback_t cb, void* ud) {
    auto* w = reinterpret_cast<VADDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.vad_set_callback) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.vad_set_callback(w->inner, cb, ud);
}

// --- Embed --------------------------------------------------------------

ra_status_t ra_embed_create(const ra_model_spec_t*     spec,
                             const ra_session_config_t* cfg,
                             ra_embed_session_t**       out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select(RA_PRIMITIVE_EMBED, spec);
    if (!plugin || !plugin->vtable.embed_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_embed_session_t* inner = nullptr;
    const auto rc = plugin->vtable.embed_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;

    auto* w = new (std::nothrow) EmbedDispatch{plugin, inner};
    if (!w) {
        if (plugin->vtable.embed_destroy) plugin->vtable.embed_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_embed_session_t*>(w);
    return RA_OK;
}

void ra_embed_destroy(ra_embed_session_t* session) {
    auto* w = reinterpret_cast<EmbedDispatch*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.embed_destroy && w->inner) {
        w->plugin->vtable.embed_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_embed_text(ra_embed_session_t* session, const char* text,
                           float* out, int32_t dims) {
    auto* w = reinterpret_cast<EmbedDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.embed_text) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.embed_text(w->inner, text, out, dims);
}

int32_t ra_embed_dims(ra_embed_session_t* session) {
    auto* w = reinterpret_cast<EmbedDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.embed_dims) return 0;
    return w->plugin->vtable.embed_dims(w->inner);
}

// --- Wake word ----------------------------------------------------------

ra_status_t ra_ww_create(const ra_model_spec_t* spec, const char* keyword,
                          float threshold, ra_ww_session_t** out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select(RA_PRIMITIVE_WAKE_WORD, spec);
    if (!plugin || !plugin->vtable.ww_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_ww_session_t* inner = nullptr;
    const auto rc = plugin->vtable.ww_create(spec, keyword, threshold, &inner);
    if (rc != RA_OK) return rc;

    auto* w = new (std::nothrow) WWDispatch{plugin, inner};
    if (!w) {
        if (plugin->vtable.ww_destroy) plugin->vtable.ww_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_ww_session_t*>(w);
    return RA_OK;
}

void ra_ww_destroy(ra_ww_session_t* session) {
    auto* w = reinterpret_cast<WWDispatch*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.ww_destroy && w->inner) {
        w->plugin->vtable.ww_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_ww_feed_audio(ra_ww_session_t* session, const float* pcm,
                              int32_t n, int32_t sr, uint8_t* detected) {
    auto* w = reinterpret_cast<WWDispatch*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.ww_feed_audio) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.ww_feed_audio(w->inner, pcm, n, sr, detected);
}

ra_status_t ra_ww_feed_audio_s16(ra_ww_session_t* session, const int16_t* pcm_s16,
                                  int32_t n, int32_t sr, uint8_t* detected) {
    if (!pcm_s16 || n <= 0) return RA_ERR_INVALID_ARGUMENT;
    // Convert int16 → float32 in 1/32768 normalisation (matches AudioRecord
    // PCM_16BIT scaling). Stack-buffered up to 4kB; heap fallback otherwise
    // to avoid pathological allocations on long buffers.
    constexpr int32_t kStackSamples = 1024;
    float             stack_buf[kStackSamples];
    float*            buf = stack_buf;
    std::unique_ptr<float[]> heap;
    if (n > kStackSamples) {
        heap = std::make_unique<float[]>(static_cast<std::size_t>(n));
        buf  = heap.get();
    }
    for (int32_t i = 0; i < n; ++i) {
        buf[i] = static_cast<float>(pcm_s16[i]) / 32768.0f;
    }
    return ra_ww_feed_audio(session, buf, n, sr, detected);
}

}  // extern "C"
