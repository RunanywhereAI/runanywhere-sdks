// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/diffusion-coreml/ — Apple-only Stable Diffusion plugin stub.
// Real integration links the apple/ml-stable-diffusion Swift package
// and routes diffusion_create / generate / cancel through CoreML.

#include "ra_diffusion.h"
#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>

namespace {

constexpr std::array<ra_primitive_t, 0> kPrimitives{};
constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_COREML};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_COREML};

ra_status_t diffusion_create_stub(const ra_model_spec_t*,
                                    const ra_diffusion_config_t*,
                                    ra_diffusion_session_t**) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

bool capability_check() {
#if defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(diffusion_coreml) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "diffusion_coreml";
    out_vtable->metadata.version           = "0.1.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();
    out_vtable->capability_check    = &capability_check;
    out_vtable->diffusion_create    = &diffusion_create_stub;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(diffusion_coreml)
