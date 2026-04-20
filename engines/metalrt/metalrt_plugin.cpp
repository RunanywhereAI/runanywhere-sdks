// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/metalrt/ — Apple-only MetalRT runtime plugin stub. MetalRT
// accelerates LLM inference on Apple Silicon NPUs/GPUs; this stub
// records availability so frontend `MetalRT.register()` succeeds.
// Real integration links MetalRT.framework when present at build time.

#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>

namespace {

constexpr std::array<ra_primitive_t, 1> kPrimitives{RA_PRIMITIVE_GENERATE_TEXT};
constexpr std::array<ra_model_format_t, 2> kFormats{RA_FORMAT_COREML, RA_FORMAT_MLX_SAFETENSORS};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_METAL};

ra_status_t llm_create_stub(const ra_model_spec_t*, const ra_session_config_t*,
                             ra_llm_session_t**) {
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

RA_PLUGIN_ENTRY_DECL(metalrt) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "metalrt";
    out_vtable->metadata.version           = "0.1.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();
    out_vtable->capability_check = &capability_check;
    out_vtable->llm_create       = &llm_create_stub;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(metalrt)
