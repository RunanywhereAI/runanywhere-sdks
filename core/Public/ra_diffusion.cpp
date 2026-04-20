// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_diffusion.h"
#include "ra_plugin.h"

#include "plugin_registry.h"
#include "engine_router.h"
#include "hardware_profile.h"

#include <cstdlib>
#include <new>

namespace {

struct DispatchDiffusionSession {
    ra::core::PluginHandleRef plugin;
    ra_diffusion_session_t*   inner;
};

ra::core::EngineRouter& router() {
    static ra::core::EngineRouter instance(
        ra::core::PluginRegistry::global(),
        ra::core::HardwareProfile::detect());
    return instance;
}

ra::core::PluginHandleRef select_diffusion_plugin(const ra_model_spec_t* spec) {
    ra::core::RouteRequest req;
    // Diffusion is not in ra_primitive_t today; we route by format only and
    // rely on diffusion plugins claiming RA_FORMAT_COREML / similar.
    req.primitive = RA_PRIMITIVE_UNKNOWN;
    req.format    = spec ? spec->format : RA_FORMAT_UNKNOWN;
    return router().route(req).plugin;
}

}  // namespace

extern "C" {

ra_status_t ra_diffusion_create(const ra_model_spec_t*       spec,
                                 const ra_diffusion_config_t* cfg,
                                 ra_diffusion_session_t**     out_session) {
    if (!out_session) return RA_ERR_INVALID_ARGUMENT;
    auto plugin = select_diffusion_plugin(spec);
    if (!plugin || !plugin->vtable.diffusion_create) return RA_ERR_BACKEND_UNAVAILABLE;
    ra_diffusion_session_t* inner = nullptr;
    auto rc = plugin->vtable.diffusion_create(spec, cfg, &inner);
    if (rc != RA_OK) return rc;
    auto* w = new (std::nothrow) DispatchDiffusionSession{plugin, inner};
    if (!w) {
        if (plugin->vtable.diffusion_destroy) plugin->vtable.diffusion_destroy(inner);
        return RA_ERR_OUT_OF_MEMORY;
    }
    *out_session = reinterpret_cast<ra_diffusion_session_t*>(w);
    return RA_OK;
}

void ra_diffusion_destroy(ra_diffusion_session_t* session) {
    auto* w = reinterpret_cast<DispatchDiffusionSession*>(session);
    if (!w) return;
    if (w->plugin && w->plugin->vtable.diffusion_destroy && w->inner) {
        w->plugin->vtable.diffusion_destroy(w->inner);
    }
    delete w;
}

ra_status_t ra_diffusion_generate(ra_diffusion_session_t*       session,
                                   const char*                   prompt,
                                   const ra_diffusion_options_t* options,
                                   uint8_t**                     out_png_bytes,
                                   int32_t*                      out_size) {
    auto* w = reinterpret_cast<DispatchDiffusionSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.diffusion_generate) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.diffusion_generate(
        w->inner, prompt, options, out_png_bytes, out_size);
}

ra_status_t ra_diffusion_generate_with_progress(
    ra_diffusion_session_t*           session,
    const char*                       prompt,
    const ra_diffusion_options_t*     options,
    ra_diffusion_progress_callback_t  progress_cb,
    void*                             user_data,
    uint8_t**                         out_png_bytes,
    int32_t*                          out_size) {
    auto* w = reinterpret_cast<DispatchDiffusionSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.diffusion_generate_with_progress)
        return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.diffusion_generate_with_progress(
        w->inner, prompt, options, progress_cb, user_data, out_png_bytes, out_size);
}

ra_status_t ra_diffusion_cancel(ra_diffusion_session_t* session) {
    auto* w = reinterpret_cast<DispatchDiffusionSession*>(session);
    if (!w || !w->plugin) return RA_ERR_INVALID_ARGUMENT;
    if (!w->plugin->vtable.diffusion_cancel) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return w->plugin->vtable.diffusion_cancel(w->inner);
}

void ra_diffusion_bytes_free(uint8_t* bytes) {
    if (bytes) std::free(bytes);
}

}  // extern "C"
