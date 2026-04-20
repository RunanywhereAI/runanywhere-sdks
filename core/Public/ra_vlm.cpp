// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// VLM dispatch — mirrors ra_llm_dispatch.cpp shape. Routes through
// PluginRegistry + EngineRouter to find a VLM-capable plugin and forwards
// every call through its vtable.

#include "ra_vlm.h"
#include "ra_plugin.h"

#include "plugin_registry.h"
#include "engine_router.h"
#include "hardware_profile.h"

#include <cstdlib>
#include <cstring>
#include <new>

namespace {

struct DispatchVlmSession {
    ra::core::PluginHandleRef plugin;
    ra_vlm_session_t*         inner;
};

ra::core::EngineRouter& router() {
    static ra::core::EngineRouter instance(
        ra::core::PluginRegistry::global(),
        ra::core::HardwareProfile::detect());
    return instance;
}

ra::core::PluginHandleRef select_vlm_plugin(const ra_model_spec_t* spec) {
    ra::core::RouteRequest req;
    req.primitive = RA_PRIMITIVE_VLM;
    req.format    = spec ? spec->format : RA_FORMAT_UNKNOWN;
    return router().route(req).plugin;
}

}  // namespace

extern "C" {

ra_status_t ra_vlm_create(const ra_model_spec_t*     spec,
                           const ra_session_config_t* cfg,
                           ra_vlm_session_t**         out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select_vlm_plugin(spec);
    if (!plugin || !plugin->vtable.vlm_create) return RA_ERR_BACKEND_UNAVAILABLE;
    ra_vlm_session_t* inner = nullptr;
    auto rc = plugin->vtable.vlm_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;
    auto* w = new (std::nothrow) DispatchVlmSession{plugin, inner};
    if (!w) {
        if (plugin->vtable.vlm_destroy) plugin->vtable.vlm_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_vlm_session_t*>(w);
    return RA_OK;
}

void ra_vlm_destroy(ra_vlm_session_t* session) {
    auto* w = reinterpret_cast<DispatchVlmSession*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.vlm_destroy && w->inner) {
        w->plugin->vtable.vlm_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_vlm_process(ra_vlm_session_t*       session,
                            const ra_vlm_image_t*   image,
                            const char*             prompt,
                            const ra_vlm_options_t* options,
                            char**                  out_text) {
    auto* w = reinterpret_cast<DispatchVlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.vlm_process) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.vlm_process(w->inner, image, prompt, options, out_text);
}

ra_status_t ra_vlm_process_stream(ra_vlm_session_t*       session,
                                    const ra_vlm_image_t*  image,
                                    const char*            prompt,
                                    const ra_vlm_options_t* options,
                                    ra_token_callback_t    on_token,
                                    ra_error_callback_t    on_error,
                                    void*                  user_data) {
    auto* w = reinterpret_cast<DispatchVlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.vlm_process_stream) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.vlm_process_stream(
        w->inner, image, prompt, options, on_token, on_error, user_data);
}

ra_status_t ra_vlm_cancel(ra_vlm_session_t* session) {
    auto* w = reinterpret_cast<DispatchVlmSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.vlm_cancel) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.vlm_cancel(w->inner);
}

const char* ra_vlm_get_builtin_template(ra_vlm_model_family_t family) {
    switch (family) {
        case RA_VLM_FAMILY_LLAVA:
            return "USER:\n<image>\n%s\nASSISTANT:";
        case RA_VLM_FAMILY_QWEN_VL:
            return "<|im_start|>user\n<image>\n%s<|im_end|>\n<|im_start|>assistant\n";
        case RA_VLM_FAMILY_INTERNVL:
            return "<|im_start|><|user|>\n<image>\n%s<|im_end|>\n<|im_start|><|assistant|>\n";
        case RA_VLM_FAMILY_PHI3V:
            return "<|user|>\n<|image_1|>\n%s<|end|>\n<|assistant|>\n";
        case RA_VLM_FAMILY_MOONDREAM:
            return "<image>\n\nQuestion: %s\n\nAnswer:";
        default:
            return nullptr;
    }
}

void ra_vlm_string_free(char* s) {
    if (s) std::free(s);
}

}  // extern "C"
