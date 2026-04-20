// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/onnx/ — ONNX Runtime plugin stub.
//
// Production integration links libonnxruntime + onnxruntime-genai and
// implements llm_create / llm_generate / embed_text via Ort::Session
// against Phi-3 / Qwen / Llama .onnx files. This stub registers the
// plugin metadata so frontend `ONNX.register()` calls succeed; session
// creation returns RA_ERR_CAPABILITY_UNSUPPORTED until the real ORT
// integration lands (gated behind RA_BUILD_ONNX_RUNTIME=ON).

#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>

namespace {

constexpr std::array<ra_primitive_t, 3> kPrimitives{
    RA_PRIMITIVE_GENERATE_TEXT,
    RA_PRIMITIVE_EMBED,
    RA_PRIMITIVE_TRANSCRIBE,
};

constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_ONNX};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_ORT};

ra_status_t llm_create_stub(const ra_model_spec_t*, const ra_session_config_t*,
                             ra_llm_session_t**) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

bool capability_check() { return true; }

}  // namespace

RA_PLUGIN_ENTRY_DECL(onnx) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "onnx";
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

RA_STATIC_PLUGIN_REGISTER(onnx)
