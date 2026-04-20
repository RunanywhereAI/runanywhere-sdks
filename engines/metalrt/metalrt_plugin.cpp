// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/metalrt/ — Apple-only MetalRT runtime plugin.
//
// MetalRT is an Apple-internal closed-source SDK that accelerates LLM
// inference on Apple Silicon NPUs/GPUs. The real integration is gated
// behind `RA_METALRT_SDK_DIR` (the build-system points at an SDK
// checkout). The Swift side can additionally inject fully-custom
// generate logic via `ra_metalrt_set_callbacks` — same pattern as
// the WhisperKit / Diffusion plugins.

#include "ra_backends.h"
#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>
#include <cstring>
#include <mutex>
#include <string>

namespace {

constexpr std::array<ra_primitive_t, 1>    kPrimitives{RA_PRIMITIVE_GENERATE_TEXT};
constexpr std::array<ra_model_format_t, 2> kFormats{RA_FORMAT_COREML, RA_FORMAT_MLX_SAFETENSORS};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_METAL};

std::mutex                   g_cb_mu;
ra_metalrt_callbacks_t       g_callbacks{};
bool                         g_installed = false;

struct SessionImpl {
    ra_metalrt_llm_handle_t swift_handle = nullptr;
};

bool capability_check() {
#if defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

ra_status_t llm_create(const ra_model_spec_t*      spec,
                         const ra_session_config_t* /*cfg*/,
                         ra_llm_session_t**          out_session) {
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
    *out_session = reinterpret_cast<ra_llm_session_t*>(impl);
    return RA_OK;
}

void llm_destroy(ra_llm_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.destroy && impl->swift_handle) {
        g_callbacks.destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

struct TokenAdapter {
    ra_token_callback_t on_token;
    void*               user_data;
};

void token_trampoline(const char* text, int32_t is_final, void* ud) {
    auto* adapter = static_cast<TokenAdapter*>(ud);
    if (!adapter || !adapter->on_token) return;
    ra_token_output_t token{};
    token.text       = text;
    token.is_final   = is_final ? 1 : 0;
    token.token_kind = 1;
    adapter->on_token(&token, adapter->user_data);
}

ra_status_t llm_generate(ra_llm_session_t*   session,
                           const ra_prompt_t*  prompt,
                           ra_token_callback_t on_token,
                           ra_error_callback_t /*on_error*/,
                           void*               user_data) {
    if (!session || !prompt || !prompt->text) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.generate) return RA_ERR_CAPABILITY_UNSUPPORTED;
    TokenAdapter adapter{on_token, user_data};
    return g_callbacks.generate(impl->swift_handle,
                                  prompt->text,
                                  &token_trampoline,
                                  &adapter,
                                  g_callbacks.user_data);
}

ra_status_t llm_cancel(ra_llm_session_t* session) {
    if (!session) return RA_ERR_INVALID_ARGUMENT;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.cancel && impl->swift_handle) {
        return g_callbacks.cancel(impl->swift_handle, g_callbacks.user_data);
    }
    return RA_OK;
}

}  // namespace

extern "C" {

ra_status_t ra_metalrt_set_callbacks(const ra_metalrt_callbacks_t* callbacks) {
    if (!callbacks || !callbacks->create || !callbacks->destroy ||
        !callbacks->generate) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard lk(g_cb_mu);
    g_callbacks = *callbacks;
    g_installed = true;
    return RA_OK;
}

uint8_t ra_metalrt_has_callbacks(void) {
    std::lock_guard lk(g_cb_mu);
    return g_installed ? 1 : 0;
}

}  // extern "C"

RA_PLUGIN_ENTRY_DECL(metalrt) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "metalrt";
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
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(metalrt)
