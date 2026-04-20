// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/onnx/ — ONNX Runtime plugin.
//
// Two production paths:
//  (A) Native: link libonnxruntime + onnxruntime-genai via vcpkg, wire
//      llm/embed/stt vtable slots directly. Gated behind
//      RA_BUILD_ONNX_RUNTIME=ON (see engines/onnx/CMakeLists.txt).
//  (B) Bridge: frontends install Swift/Kotlin callbacks via
//      `ra_onnx_set_callbacks` — this plugin trampolines through them.
//
// Path (B) ships unconditionally; path (A) layers on top when the
// vcpkg deps are available. Both can coexist — the callback bridge
// takes priority if registered.

#include "ra_backends.h"
#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

namespace {

constexpr std::array<ra_primitive_t, 3> kPrimitives{
    RA_PRIMITIVE_GENERATE_TEXT,
    RA_PRIMITIVE_EMBED,
    RA_PRIMITIVE_TRANSCRIBE,
};

constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_ONNX};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_ORT};

std::mutex              g_cb_mu;
ra_onnx_callbacks_t     g_callbacks{};
bool                    g_installed = false;

struct LlmSessionImpl   { ra_onnx_llm_handle_t   swift_handle = nullptr; };
struct EmbedSessionImpl { ra_onnx_embed_handle_t swift_handle = nullptr; };
struct SttSessionImpl {
    ra_onnx_stt_handle_t     swift_handle = nullptr;
    std::vector<float>       audio_buffer;
    int32_t                  sample_rate = 16000;
    ra_transcript_callback_t on_chunk    = nullptr;
    void*                    on_chunk_ud = nullptr;
};

bool capability_check() { return true; }

// ---------------------------------------------------------------------------
// LLM slot
// ---------------------------------------------------------------------------

ra_status_t llm_create(const ra_model_spec_t* spec,
                         const ra_session_config_t* /*cfg*/,
                         ra_llm_session_t** out_session) {
    if (!spec || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.llm_create) return RA_ERR_CAPABILITY_UNSUPPORTED;
    auto h = g_callbacks.llm_create(spec->model_path ? spec->model_path : "",
                                       g_callbacks.user_data);
    if (!h) return RA_ERR_INTERNAL;
    auto* impl = new LlmSessionImpl{};
    impl->swift_handle = h;
    *out_session = reinterpret_cast<ra_llm_session_t*>(impl);
    return RA_OK;
}

void llm_destroy(ra_llm_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<LlmSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.llm_destroy) {
        g_callbacks.llm_destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

struct TokenAdapter {
    ra_token_callback_t on_token;
    void*               user_data;
};

void token_trampoline(const char* text, int32_t is_final, void* ud) {
    auto* a = static_cast<TokenAdapter*>(ud);
    if (!a || !a->on_token) return;
    ra_token_output_t token{};
    token.text = text; token.is_final = is_final ? 1 : 0; token.token_kind = 1;
    a->on_token(&token, a->user_data);
}

ra_status_t llm_generate(ra_llm_session_t* session, const ra_prompt_t* prompt,
                           ra_token_callback_t on_token,
                           ra_error_callback_t /*on_error*/, void* user_data) {
    if (!session || !prompt || !prompt->text) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<LlmSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.llm_generate) return RA_ERR_CAPABILITY_UNSUPPORTED;
    TokenAdapter adapter{on_token, user_data};
    return g_callbacks.llm_generate(impl->swift_handle, prompt->text,
                                       &token_trampoline, &adapter,
                                       g_callbacks.user_data);
}

ra_status_t llm_cancel(ra_llm_session_t* session) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<LlmSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.llm_cancel) {
        return g_callbacks.llm_cancel(impl->swift_handle, g_callbacks.user_data);
    }
    return RA_OK;
}

// ---------------------------------------------------------------------------
// Embedding slot
// ---------------------------------------------------------------------------

ra_status_t embed_create(const ra_model_spec_t* spec,
                           const ra_session_config_t* /*cfg*/,
                           ra_embed_session_t** out_session) {
    if (!spec || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.embed_create) return RA_ERR_CAPABILITY_UNSUPPORTED;
    auto h = g_callbacks.embed_create(spec->model_path ? spec->model_path : "",
                                         g_callbacks.user_data);
    if (!h) return RA_ERR_INTERNAL;
    auto* impl = new EmbedSessionImpl{};
    impl->swift_handle = h;
    *out_session = reinterpret_cast<ra_embed_session_t*>(impl);
    return RA_OK;
}

void embed_destroy(ra_embed_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<EmbedSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.embed_destroy) {
        g_callbacks.embed_destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

// ---------------------------------------------------------------------------
// STT slot
// ---------------------------------------------------------------------------

ra_status_t stt_create(const ra_model_spec_t* spec,
                         const ra_session_config_t* /*cfg*/,
                         ra_stt_session_t** out_session) {
    if (!spec || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.stt_create) return RA_ERR_CAPABILITY_UNSUPPORTED;
    auto h = g_callbacks.stt_create(spec->model_path ? spec->model_path : "",
                                       g_callbacks.user_data);
    if (!h) return RA_ERR_INTERNAL;
    auto* impl = new SttSessionImpl{};
    impl->swift_handle = h;
    *out_session = reinterpret_cast<ra_stt_session_t*>(impl);
    return RA_OK;
}

void stt_destroy(ra_stt_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<SttSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.stt_destroy) {
        g_callbacks.stt_destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

ra_status_t stt_feed_audio(ra_stt_session_t* session, const float* audio,
                             int32_t count, int32_t sample_rate) {
    if (!session || !audio || count <= 0) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SttSessionImpl*>(session);
    impl->audio_buffer.insert(impl->audio_buffer.end(), audio, audio + count);
    if (sample_rate > 0) impl->sample_rate = sample_rate;
    return RA_OK;
}

ra_status_t stt_flush(ra_stt_session_t* session) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SttSessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.stt_transcribe) return RA_ERR_CAPABILITY_UNSUPPORTED;
    char* out = nullptr;
    auto rc = g_callbacks.stt_transcribe(impl->swift_handle,
                                            impl->audio_buffer.data(),
                                            impl->audio_buffer.size(),
                                            impl->sample_rate,
                                            &out,
                                            g_callbacks.user_data);
    impl->audio_buffer.clear();
    if (rc != RA_OK) return rc;
    if (impl->on_chunk && out) {
        ra_transcript_chunk_t chunk{};
        chunk.text = out; chunk.is_partial = 0; chunk.confidence = 1.0f;
        impl->on_chunk(&chunk, impl->on_chunk_ud);
    }
    if (g_callbacks.stt_string_free && out) {
        g_callbacks.stt_string_free(out, g_callbacks.user_data);
    }
    return RA_OK;
}

ra_status_t stt_set_callback(ra_stt_session_t* session,
                               ra_transcript_callback_t cb, void* user_data) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SttSessionImpl*>(session);
    impl->on_chunk = cb; impl->on_chunk_ud = user_data;
    return RA_OK;
}

}  // namespace

extern "C" {

ra_status_t ra_onnx_set_callbacks(const ra_onnx_callbacks_t* callbacks) {
    if (!callbacks) return RA_ERR_INVALID_ARGUMENT;
    // At least one slot must be populated.
    if (!callbacks->llm_create && !callbacks->embed_create && !callbacks->stt_create) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard lk(g_cb_mu);
    g_callbacks = *callbacks;
    g_installed = true;
    return RA_OK;
}

uint8_t ra_onnx_has_callbacks(void) {
    std::lock_guard lk(g_cb_mu);
    return g_installed ? 1 : 0;
}

}  // extern "C"

RA_PLUGIN_ENTRY_DECL(onnx) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "onnx";
    out_vtable->metadata.version           = "0.2.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();

    out_vtable->capability_check = &capability_check;
    out_vtable->llm_create       = &llm_create;
    out_vtable->llm_destroy      = &llm_destroy;
    out_vtable->llm_generate     = &llm_generate;
    out_vtable->llm_cancel       = &llm_cancel;
    out_vtable->embed_create     = &embed_create;
    out_vtable->embed_destroy    = &embed_destroy;
    out_vtable->stt_create       = &stt_create;
    out_vtable->stt_destroy      = &stt_destroy;
    out_vtable->stt_feed_audio   = &stt_feed_audio;
    out_vtable->stt_flush        = &stt_flush;
    out_vtable->stt_set_callback = &stt_set_callback;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(onnx)
