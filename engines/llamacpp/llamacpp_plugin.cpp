// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// llama.cpp L2 engine plugin — thin C wrapper over the llama.cpp library.
//
// This file intentionally keeps the glue minimal. The full decode loop lives
// in llamacpp_engine.cpp, which holds the LlamaSession class. The plugin
// surface is just function pointers into that class's static adapters.
//
// For the MVP we ship stub implementations that succeed at create/destroy but
// return RA_ERR_RUNTIME_UNAVAILABLE at generate. The real llama.cpp integration
// is in the next PR (tracked by the Phase 0 llamacpp_engine agent).

#include "llamacpp_plugin.h"

#include <array>
#include <cstring>
#include <new>
#include <string>

#include "ra_primitives.h"

namespace {

// Opaque session — heap-allocated, returned as ra_llm_session_t* by cast.
struct LlamaSession {
    std::string model_path;
    int         n_gpu_layers = -1;
    int         n_threads    = 0;
    int         context_size = 4096;
};

constexpr std::array<ra_primitive_t, 2> kPrimitives = {
    RA_PRIMITIVE_GENERATE_TEXT, RA_PRIMITIVE_EMBED
};
constexpr std::array<ra_model_format_t, 1> kFormats   = { RA_FORMAT_GGUF };
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes  = { RA_RUNTIME_SELF_CONTAINED };

bool capability_check() {
    // llama.cpp supports every platform — always available.
    return true;
}

// ---- LLM ----
ra_status_t llm_create(const ra_model_spec_t*     spec,
                       const ra_session_config_t* cfg,
                       ra_llm_session_t**         out) {
    if (!spec || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) LlamaSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    if (cfg) {
        s->n_gpu_layers = cfg->n_gpu_layers;
        s->n_threads    = cfg->n_threads;
        s->context_size = cfg->context_size ? cfg->context_size : 4096;
    }
    *out = reinterpret_cast<ra_llm_session_t*>(s);
    return RA_OK;
}

void llm_destroy(ra_llm_session_t* session) {
    delete reinterpret_cast<LlamaSession*>(session);
}

ra_status_t llm_generate(ra_llm_session_t*   /*session*/,
                          const ra_prompt_t*  /*prompt*/,
                          ra_token_callback_t /*on_token*/,
                          ra_error_callback_t on_error,
                          void*               user_data) {
    if (on_error) {
        on_error(RA_ERR_RUNTIME_UNAVAILABLE,
                 "llama.cpp integration not yet wired — stub plugin",
                 user_data);
    }
    return RA_ERR_RUNTIME_UNAVAILABLE;
}

ra_status_t llm_cancel(ra_llm_session_t* /*session*/) {
    return RA_OK;
}

ra_status_t llm_reset(ra_llm_session_t* /*session*/) {
    return RA_OK;
}

// ---- Embed (same llama.cpp runtime can embed) ----
ra_status_t embed_create(const ra_model_spec_t* spec,
                          const ra_session_config_t* /*cfg*/,
                          ra_embed_session_t** out) {
    if (!spec || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) LlamaSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    *out = reinterpret_cast<ra_embed_session_t*>(s);
    return RA_OK;
}

void embed_destroy(ra_embed_session_t* s) {
    delete reinterpret_cast<LlamaSession*>(s);
}

ra_status_t embed_text(ra_embed_session_t* /*session*/,
                        const char*         /*text*/,
                        float*              out_vec,
                        int                 dims) {
    if (!out_vec || dims <= 0) return RA_ERR_INVALID_ARGUMENT;
    std::memset(out_vec, 0, sizeof(float) * static_cast<std::size_t>(dims));
    return RA_ERR_RUNTIME_UNAVAILABLE;
}

int32_t embed_dims(ra_embed_session_t* /*session*/) {
    return 384;  // typical bge-small dimension
}

}  // namespace

extern "C" ra_status_t ra_plugin_entry(ra_engine_vtable_t* out) {
    if (!out) return RA_ERR_INVALID_ARGUMENT;
    *out = {};
    out->metadata.name              = "llamacpp";
    out->metadata.version           = "0.1.0";
    out->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out->metadata.primitives        = kPrimitives.data();
    out->metadata.primitives_count  = kPrimitives.size();
    out->metadata.formats           = kFormats.data();
    out->metadata.formats_count     = kFormats.size();
    out->metadata.runtimes          = kRuntimes.data();
    out->metadata.runtimes_count    = kRuntimes.size();

    out->capability_check = &capability_check;

    out->llm_create   = &llm_create;
    out->llm_destroy  = &llm_destroy;
    out->llm_generate = &llm_generate;
    out->llm_cancel   = &llm_cancel;
    out->llm_reset    = &llm_reset;

    out->embed_create  = &embed_create;
    out->embed_destroy = &embed_destroy;
    out->embed_text    = &embed_text;
    out->embed_dims    = &embed_dims;
    return RA_OK;
}

// Static-mode registration (iOS/WASM).
RA_STATIC_PLUGIN_REGISTER(llamacpp, ra_plugin_entry)
