// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/diffusion-coreml/ — CoreML Stable Diffusion plugin.
// Delegates to Swift via a registered callback table installed through
// `ra_diffusion_coreml_set_callbacks` (declared in ra_backends.h).
//
// The ml-stable-diffusion SPM package lives on the Swift side;
// `DiffusionCoreMLService.swift` installs the callback table.

#include "ra_backends.h"
#include "ra_diffusion.h"
#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>
#include <cstring>
#include <mutex>
#include <string>

namespace {

constexpr std::array<ra_primitive_t, 0>    kPrimitives{};
constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_COREML};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_COREML};

std::mutex                              g_cb_mu;
ra_diffusion_coreml_callbacks_t         g_callbacks{};
bool                                    g_installed = false;

struct SessionImpl {
    ra_diffusion_coreml_handle_t swift_handle = nullptr;
    std::string                  model_folder;
    // Capture the generation config at create time — ra_diffusion_options_t
    // doesn't carry width/height/steps (those live on ra_diffusion_config_t
    // which is only passed into create). The plugin snapshots it so
    // generate() can pass the full set to Swift.
    int32_t                      width          = 512;
    int32_t                      height         = 512;
    int32_t                      steps          = 20;
    float                        guidance_scale = 7.5f;
    int64_t                      seed           = -1;
};

bool capability_check() {
#if defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

ra_status_t diffusion_create(const ra_model_spec_t*        spec,
                               const ra_diffusion_config_t* cfg,
                               ra_diffusion_session_t**     out_session) {
    if (!spec || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.create) {
        return RA_ERR_CAPABILITY_UNSUPPORTED;
    }
    // 2 = cpu+gpu+neural engine (all). Swift side maps to MLComputeUnits.
    const int32_t compute_units = 2;
    auto handle = g_callbacks.create(
        spec->model_path ? spec->model_path : "",
        compute_units,
        g_callbacks.user_data);
    if (!handle) return RA_ERR_INTERNAL;

    auto* impl = new SessionImpl{};
    impl->swift_handle = handle;
    impl->model_folder = spec->model_path ? spec->model_path : "";
    if (cfg) {
        if (cfg->width  > 0) impl->width  = cfg->width;
        if (cfg->height > 0) impl->height = cfg->height;
        if (cfg->num_inference_steps > 0) impl->steps = cfg->num_inference_steps;
        if (cfg->guidance_scale > 0)      impl->guidance_scale = cfg->guidance_scale;
        impl->seed = cfg->seed;
    }

    *out_session = reinterpret_cast<ra_diffusion_session_t*>(impl);
    return RA_OK;
}

void diffusion_destroy(ra_diffusion_session_t* session) {
    if (!session) return;
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (g_installed && g_callbacks.destroy && impl->swift_handle) {
        g_callbacks.destroy(impl->swift_handle, g_callbacks.user_data);
    }
    delete impl;
}

ra_status_t diffusion_generate(ra_diffusion_session_t*       session,
                                 const char*                   prompt,
                                 const ra_diffusion_options_t* options,
                                 uint8_t**                     out_png_bytes,
                                 int32_t*                      out_size) {
    if (!session || !prompt || !out_png_bytes || !out_size) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.generate) return RA_ERR_CAPABILITY_UNSUPPORTED;

    const char* neg = options ? options->negative_prompt : nullptr;
    uint8_t* png = nullptr;
    int32_t  size = 0;
    auto rc = g_callbacks.generate(
        impl->swift_handle,
        prompt, neg,
        impl->seed, impl->steps, impl->guidance_scale,
        impl->width, impl->height,
        nullptr, nullptr,
        &png, &size,
        g_callbacks.user_data);
    if (rc != RA_OK) return rc;

    // Copy into C-owned heap so the caller frees via ra_diffusion_bytes_free
    // (which plays by the v2 allocator).
    auto* copy = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(size)));
    if (!copy) {
        if (g_callbacks.bytes_free) g_callbacks.bytes_free(png, g_callbacks.user_data);
        return RA_ERR_OUT_OF_MEMORY;
    }
    std::memcpy(copy, png, static_cast<size_t>(size));
    if (g_callbacks.bytes_free) g_callbacks.bytes_free(png, g_callbacks.user_data);
    *out_png_bytes = copy;
    *out_size      = size;
    return RA_OK;
}

ra_status_t diffusion_generate_with_progress(
    ra_diffusion_session_t*        session,
    const char*                    prompt,
    const ra_diffusion_options_t*  options,
    void (*progress_cb)(int32_t step, int32_t total, void* user),
    void*                          user_data,
    uint8_t**                      out_png_bytes,
    int32_t*                       out_size) {
    if (!session || !prompt || !out_png_bytes || !out_size) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    auto* impl = reinterpret_cast<SessionImpl*>(session);
    std::lock_guard lk(g_cb_mu);
    if (!g_installed || !g_callbacks.generate) return RA_ERR_CAPABILITY_UNSUPPORTED;
    const char* neg = options ? options->negative_prompt : nullptr;
    uint8_t* png = nullptr;
    int32_t  size = 0;
    auto rc = g_callbacks.generate(
        impl->swift_handle,
        prompt, neg,
        impl->seed, impl->steps, impl->guidance_scale,
        impl->width, impl->height,
        progress_cb, user_data,
        &png, &size,
        g_callbacks.user_data);
    if (rc != RA_OK) return rc;
    auto* copy = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(size)));
    if (!copy) {
        if (g_callbacks.bytes_free) g_callbacks.bytes_free(png, g_callbacks.user_data);
        return RA_ERR_OUT_OF_MEMORY;
    }
    std::memcpy(copy, png, static_cast<size_t>(size));
    if (g_callbacks.bytes_free) g_callbacks.bytes_free(png, g_callbacks.user_data);
    *out_png_bytes = copy;
    *out_size      = size;
    return RA_OK;
}

ra_status_t diffusion_cancel(ra_diffusion_session_t* session) {
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

ra_status_t ra_diffusion_coreml_set_callbacks(
    const ra_diffusion_coreml_callbacks_t* callbacks) {
    if (!callbacks || !callbacks->create || !callbacks->destroy ||
        !callbacks->generate || !callbacks->bytes_free) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    std::lock_guard lk(g_cb_mu);
    g_callbacks = *callbacks;
    g_installed = true;
    return RA_OK;
}

uint8_t ra_diffusion_coreml_has_callbacks(void) {
    std::lock_guard lk(g_cb_mu);
    return g_installed ? 1 : 0;
}

}  // extern "C"

RA_PLUGIN_ENTRY_DECL(diffusion_coreml) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "diffusion_coreml";
    out_vtable->metadata.version           = "0.2.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();
    out_vtable->capability_check                  = &capability_check;
    out_vtable->diffusion_create                  = &diffusion_create;
    out_vtable->diffusion_destroy                 = &diffusion_destroy;
    out_vtable->diffusion_generate                = &diffusion_generate;
    out_vtable->diffusion_generate_with_progress  = &diffusion_generate_with_progress;
    out_vtable->diffusion_cancel                  = &diffusion_cancel;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(diffusion_coreml)
