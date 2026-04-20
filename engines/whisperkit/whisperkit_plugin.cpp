// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/whisperkit/ — Apple WhisperKit STT plugin.
//
// The WhisperKit SPM package + CoreML weights live on the Swift side.
// `sdk/swift/Sources/Backends/WhisperKitRuntime/WhisperKitSTTService.swift`
// installs a callback table via `ra_whisperkit_set_callbacks`; this
// plugin's STT vtable trampolines through those callbacks.
//
// Non-Apple builds report RA_ERR_CAPABILITY_UNSUPPORTED and all vtable
// slots bail out with invalid-argument.

#include "ra_plugin.h"
#include "ra_primitives.h"
#include "whisperkit_bridge.h"

#include <array>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr std::array<ra_primitive_t, 1>    kPrimitives{RA_PRIMITIVE_TRANSCRIBE};
constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_WHISPERKIT};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_COREML};

std::mutex                    g_cb_mu;
ra_whisperkit_callbacks_t     g_callbacks{};
bool                          g_installed = false;

struct SessionImpl {
    ra_whisperkit_session_handle_t swift_handle = nullptr;
    int32_t                        sample_rate  = 16000;
    std::string                    language     = "en";
    std::vector<float>             audio_buffer;
    ra_transcript_callback_t       on_chunk     = nullptr;
    void*                          on_chunk_ud  = nullptr;
};

bool capability_check() {
#if defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

ra_status_t stt_create(const ra_model_spec_t*     spec,
                        const ra_session_config_t* cfg,
                        ra_stt_session_t**         out_session) {
    if (!spec || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.create) {
        return RA_ERR_CAPABILITY_UNSUPPORTED;
    }
    auto handle = g_callbacks.create(spec->model_path ? spec->model_path : "",
                                      g_callbacks.user_data);
    if (!handle) return RA_ERR_INTERNAL;

    auto* impl = new SessionImpl{};
    impl->swift_handle = handle;
    (void)cfg;  // v2 ra_session_config_t has no sample_rate_hz; default 16k

    *out_session = reinterpret_cast<ra_stt_session_t*>(impl);
    return RA_OK;
}

void stt_destroy(ra_stt_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.destroy && impl->swift_handle) {
        g_callbacks.destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

ra_status_t stt_feed_audio(ra_stt_session_t* session,
                             const float*     audio,
                             int32_t          sample_count,
                             int32_t          /* sample_rate_hz */) {
    if (!session || !audio || sample_count <= 0) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    impl->audio_buffer.insert(impl->audio_buffer.end(),
                                audio, audio + sample_count);
    return RA_OK;
}

ra_status_t stt_flush(ra_stt_session_t* session) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SessionImpl*>(session);

    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.transcribe) return RA_ERR_CAPABILITY_UNSUPPORTED;

    char* out_text = nullptr;
    auto rc = g_callbacks.transcribe(
        impl->swift_handle,
        impl->audio_buffer.data(), impl->audio_buffer.size(),
        impl->sample_rate,
        impl->language.c_str(),
        &out_text,
        g_callbacks.user_data);
    impl->audio_buffer.clear();
    if (rc != RA_OK) return rc;
    if (impl->on_chunk && out_text) {
        ra_transcript_chunk_t chunk{};
        chunk.text       = out_text;
        chunk.is_partial = 0;
        chunk.confidence = 1.0f;
        impl->on_chunk(&chunk, impl->on_chunk_ud);
    }
    if (g_callbacks.string_free && out_text) {
        g_callbacks.string_free(out_text, g_callbacks.user_data);
    }
    return RA_OK;
}

ra_status_t stt_set_callback(ra_stt_session_t*        session,
                               ra_transcript_callback_t cb,
                               void*                    user_data) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    impl->on_chunk    = cb;
    impl->on_chunk_ud = user_data;
    return RA_OK;
}

}  // namespace

extern "C" {

ra_status_t ra_whisperkit_set_callbacks(
    const ra_whisperkit_callbacks_t* callbacks) {
    if (!callbacks || !callbacks->create || !callbacks->destroy ||
        !callbacks->transcribe || !callbacks->string_free) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard lk(g_cb_mu);
    g_callbacks = *callbacks;
    g_installed = true;
    return RA_OK;
}

uint8_t ra_whisperkit_has_callbacks(void) {
    std::lock_guard lk(g_cb_mu);
    return g_installed ? 1 : 0;
}

}  // extern "C"

RA_PLUGIN_ENTRY_DECL(whisperkit) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "whisperkit";
    out_vtable->metadata.version           = "0.2.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();
    out_vtable->capability_check = &capability_check;
    out_vtable->stt_create        = &stt_create;
    out_vtable->stt_destroy       = &stt_destroy;
    out_vtable->stt_feed_audio    = &stt_feed_audio;
    out_vtable->stt_flush         = &stt_flush;
    out_vtable->stt_set_callback  = &stt_set_callback;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(whisperkit)
