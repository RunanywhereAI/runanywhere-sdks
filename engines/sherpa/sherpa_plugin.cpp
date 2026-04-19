// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// sherpa-onnx L2 engine plugin — implements transcribe, synthesize, and
// detect_voice primitives over ONNX models.

#include <array>
#include <cstring>
#include <new>
#include <string>

#include "ra_plugin.h"
#include "ra_primitives.h"

namespace {

struct SherpaSttSession {
    std::string model_path;
    int         sample_rate = 16000;
};

struct SherpaTtsSession {
    std::string model_path;
};

struct SherpaVadSession {
    std::string model_path;
    ra_vad_callback_t cb         = nullptr;
    void*             cb_userdata = nullptr;
};

constexpr std::array<ra_primitive_t, 3> kPrimitives = {
    RA_PRIMITIVE_TRANSCRIBE,
    RA_PRIMITIVE_SYNTHESIZE,
    RA_PRIMITIVE_DETECT_VOICE,
};
constexpr std::array<ra_model_format_t, 1> kFormats  = { RA_FORMAT_ONNX };
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes = { RA_RUNTIME_ORT };

// ---- STT ----
ra_status_t stt_create(const ra_model_spec_t* spec,
                        const ra_session_config_t* /*cfg*/,
                        ra_stt_session_t** out) {
    if (!spec || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) SherpaSttSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    *out = reinterpret_cast<ra_stt_session_t*>(s);
    return RA_OK;
}

void stt_destroy(ra_stt_session_t* s) {
    delete reinterpret_cast<SherpaSttSession*>(s);
}

ra_status_t stt_feed_audio(ra_stt_session_t* /*s*/,
                            const float* /*pcm*/,
                            int32_t /*n*/, int32_t /*sr*/) {
    return RA_ERR_RUNTIME_UNAVAILABLE;
}

ra_status_t stt_flush(ra_stt_session_t* /*s*/) { return RA_OK; }

ra_status_t stt_set_callback(ra_stt_session_t* /*s*/,
                              ra_transcript_callback_t /*cb*/,
                              void* /*ud*/) {
    return RA_OK;
}

// ---- TTS ----
ra_status_t tts_create(const ra_model_spec_t* spec,
                        const ra_session_config_t* /*cfg*/,
                        ra_tts_session_t** out) {
    if (!spec || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) SherpaTtsSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    *out = reinterpret_cast<ra_tts_session_t*>(s);
    return RA_OK;
}

void tts_destroy(ra_tts_session_t* s) {
    delete reinterpret_cast<SherpaTtsSession*>(s);
}

ra_status_t tts_synthesize(ra_tts_session_t* /*s*/,
                            const char* /*text*/,
                            float* /*out_pcm*/,
                            int32_t /*max*/,
                            int32_t* written,
                            int32_t* sr) {
    if (written) *written = 0;
    if (sr)      *sr      = 24000;
    return RA_ERR_RUNTIME_UNAVAILABLE;
}

ra_status_t tts_cancel(ra_tts_session_t* /*s*/) { return RA_OK; }

// ---- VAD ----
ra_status_t vad_create(const ra_model_spec_t* spec,
                        const ra_session_config_t* /*cfg*/,
                        ra_vad_session_t** out) {
    if (!spec || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) SherpaVadSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    *out = reinterpret_cast<ra_vad_session_t*>(s);
    return RA_OK;
}

void vad_destroy(ra_vad_session_t* s) {
    delete reinterpret_cast<SherpaVadSession*>(s);
}

ra_status_t vad_feed_audio(ra_vad_session_t* /*s*/,
                            const float* /*pcm*/,
                            int32_t /*n*/, int32_t /*sr*/) {
    return RA_ERR_RUNTIME_UNAVAILABLE;
}

ra_status_t vad_set_callback(ra_vad_session_t* s,
                              ra_vad_callback_t cb,
                              void* ud) {
    auto* session = reinterpret_cast<SherpaVadSession*>(s);
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    session->cb          = cb;
    session->cb_userdata = ud;
    return RA_OK;
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(sherpa) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "sherpa";
    out_vtable->metadata.version           = "0.1.0";
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
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(sherpa)
