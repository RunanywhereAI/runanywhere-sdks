// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/genie/ — Android-only Qualcomm Genie LLM plugin stub.

#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>

namespace {

constexpr std::array<ra_primitive_t, 1> kPrimitives{RA_PRIMITIVE_GENERATE_TEXT};
constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_UNKNOWN};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_SELF_CONTAINED};

ra_status_t llm_create_stub(const ra_model_spec_t*, const ra_session_config_t*,
                             ra_llm_session_t**) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

bool capability_check() {
#if defined(__ANDROID__)
    return true;
#else
    return false;
#endif
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(genie) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "genie";
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

RA_STATIC_PLUGIN_REGISTER(genie)
