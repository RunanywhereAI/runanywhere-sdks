// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// C ABI dispatch layer for LLM primitives. Frontends call
// `ra_llm_create(spec, cfg, &session)` — this file resolves the spec
// against the plugin registry, forwards to the chosen engine's vtable,
// and wraps the raw session inside a typed handle that carries the
// vtable pointer so subsequent calls (generate / inject_system_prompt /
// append_context / …) can dispatch back through the same engine.
//
// Without this layer, ra_llm_* would only be "extern" declarations
// resolved by -undefined dynamic_lookup against a specific engine
// plugin — fine for bundled builds, broken for any dynamic routing.

#include "ra_primitives.h"
#include "ra_plugin.h"

#include "../registry/plugin_registry.h"
#include "../router/engine_router.h"
#include "../router/hardware_profile.h"

#include <memory>
#include <mutex>
#include <new>

namespace {

struct DispatchLlmSession {
    ra::core::PluginHandleRef plugin;  // keeps vtable alive
    ra_llm_session_t*         inner;   // engine-owned session
};

ra::core::EngineRouter& router() {
    static ra::core::EngineRouter instance(
        ra::core::PluginRegistry::global(),
        ra::core::HardwareProfile::detect());
    return instance;
}

ra::core::PluginHandleRef select_llm_plugin(const ra_model_spec_t* spec) {
    ra::core::RouteRequest req;
    req.primitive = RA_PRIMITIVE_GENERATE_TEXT;
    req.format    = spec ? spec->format : RA_FORMAT_UNKNOWN;
    return router().route(req).plugin;
}

}  // namespace

extern "C" {

ra_status_t ra_llm_create(const ra_model_spec_t*     spec,
                           const ra_session_config_t* cfg,
                           ra_llm_session_t**         out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select_llm_plugin(spec);
    if (!plugin || !plugin->vtable.llm_create) return RA_ERR_BACKEND_UNAVAILABLE;

    ra_llm_session_t* inner = nullptr;
    const auto rc = plugin->vtable.llm_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;

    auto* wrapper = new (std::nothrow) DispatchLlmSession{plugin, inner};
    if (!wrapper) {
        if (plugin->vtable.llm_destroy) plugin->vtable.llm_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_llm_session_t*>(wrapper);
    return RA_OK;
}

void ra_llm_destroy(ra_llm_session_t* session) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.llm_destroy && w->inner) {
        w->plugin->vtable.llm_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_llm_generate(ra_llm_session_t*   session,
                             const ra_prompt_t*  prompt,
                             ra_token_callback_t on_token,
                             ra_error_callback_t on_error,
                             void*               user_data) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.llm_generate) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.llm_generate(w->inner, prompt, on_token, on_error, user_data);
}

ra_status_t ra_llm_cancel(ra_llm_session_t* session) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.llm_cancel) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.llm_cancel(w->inner);
}

ra_status_t ra_llm_reset(ra_llm_session_t* session) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin || !w->plugin->vtable.llm_reset) return RA_ERR_INVALID_ARGUMENT;
    return w->plugin->vtable.llm_reset(w->inner);
}

ra_status_t ra_llm_inject_system_prompt(ra_llm_session_t* session,
                                         const char*       prompt) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.llm_inject_system_prompt) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.llm_inject_system_prompt(w->inner, prompt);
}

ra_status_t ra_llm_append_context(ra_llm_session_t* session,
                                   const char*       text) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.llm_append_context) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.llm_append_context(w->inner, text);
}

ra_status_t ra_llm_generate_from_context(ra_llm_session_t*   session,
                                          const char*         query,
                                          ra_token_callback_t on_token,
                                          ra_error_callback_t on_error,
                                          void*               user_data) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.llm_generate_from_context) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.llm_generate_from_context(
        w->inner, query, on_token, on_error, user_data);
}

ra_status_t ra_llm_clear_context(ra_llm_session_t* session) {
    auto* w = reinterpret_cast<DispatchLlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.llm_clear_context) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.llm_clear_context(w->inner);
}

}  // extern "C"
