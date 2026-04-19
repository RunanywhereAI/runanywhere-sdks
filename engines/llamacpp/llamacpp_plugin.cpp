// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// llama.cpp L2 engine plugin — real inference over the llama.cpp C API.
//
// Loads a GGUF model, tokenizes the prompt, runs a greedy decode loop,
// and emits tokens via the ra_token_callback_t as they're produced.
// Also serves the embed primitive via pooled last-layer logits.
//
// The plugin is loaded dlopen-style on macOS/Linux/Android and statically
// on iOS/WASM. Same vtable fills in both modes.

#include "llamacpp_plugin.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "llama.h"
#include "ra_primitives.h"

namespace {

// One-time llama_backend_init() / llama_backend_free() guard. Multiple
// sessions share the backend — repeated init calls are safe per the
// upstream docs, but we still only pay the cost once.
void ensure_backend_init() {
    static std::once_flag once;
    std::call_once(once, [] { ::llama_backend_init(); });
}

// ---------------------------------------------------------------------------
// LLM session
// ---------------------------------------------------------------------------
struct LlamaSession {
    ::llama_model*   model    = nullptr;
    ::llama_context* ctx      = nullptr;
    ::llama_sampler* sampler  = nullptr;
    int              n_ctx    = 4096;
    int              max_new_tokens = 512;
    std::atomic<bool> cancel_flag{false};
};

// Shared impl for llm + embed creation — both take the same spec+cfg pair.
// Returns nullptr on failure (OOM, model load error, context creation error).
// The out_status pointer receives a descriptive ra_status_t.
LlamaSession* create_common_session(const ra_model_spec_t*      spec,
                                      const ra_session_config_t*  cfg,
                                      bool                        for_embed,
                                      ra_status_t*                out_status) {
    if (!spec || !spec->model_path) {
        if (out_status) *out_status = RA_ERR_INVALID_ARGUMENT;
        return nullptr;
    }
    ensure_backend_init();

    auto* s = new (std::nothrow) LlamaSession();
    if (!s) {
        if (out_status) *out_status = RA_ERR_OUT_OF_MEMORY;
        return nullptr;
    }

    ::llama_model_params mparams = ::llama_model_default_params();
    if (cfg && cfg->n_gpu_layers >= 0) {
        mparams.n_gpu_layers = cfg->n_gpu_layers;
    }

    s->model = ::llama_load_model_from_file(spec->model_path, mparams);
    if (!s->model) {
        delete s;
        if (out_status) *out_status = RA_ERR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    ::llama_context_params cparams = ::llama_context_default_params();
    cparams.n_ctx   = cfg && cfg->context_size > 0
                      ? static_cast<uint32_t>(cfg->context_size)
                      : static_cast<uint32_t>(s->n_ctx);
    // llama.cpp b4393 asserts n_threads > 0 and does NOT resolve 0 to
    // hardware_concurrency. Caller-passed 0 means "pick a reasonable
    // default for this host" — resolve it here.
    const int hc = std::max(1,
        static_cast<int>(std::thread::hardware_concurrency()));
    const int requested = (cfg && cfg->n_threads > 0) ? cfg->n_threads : 0;
    cparams.n_threads       = requested > 0 ? requested : std::min(8, hc);
    cparams.n_threads_batch = cparams.n_threads;
    cparams.embeddings      = for_embed;

    s->ctx = ::llama_new_context_with_model(s->model, cparams);
    if (!s->ctx) {
        ::llama_free_model(s->model);
        delete s;
        if (out_status) *out_status = RA_ERR_MODEL_LOAD_FAILED;
        return nullptr;
    }
    s->n_ctx = static_cast<int>(::llama_n_ctx(s->ctx));

    // Default sampler chain: temperature -> dist. Greedy is fine for the
    // bootstrap; the frontend will configure this through the session
    // config extension fields in a follow-up commit.
    {
        ::llama_sampler_chain_params p = ::llama_sampler_chain_default_params();
        p.no_perf = true;
        s->sampler = ::llama_sampler_chain_init(p);
        ::llama_sampler_chain_add(s->sampler, ::llama_sampler_init_greedy());
    }

    if (out_status) *out_status = RA_OK;
    return s;
}

void destroy_common_session(LlamaSession* s) {
    if (!s) return;
    if (s->sampler) ::llama_sampler_free(s->sampler);
    if (s->ctx)     ::llama_free(s->ctx);
    if (s->model)   ::llama_free_model(s->model);
    delete s;
}

// Tokenize a null-terminated UTF-8 string. Returns the token count or -1
// on failure. `tokens` is sized before the call and will be resized to fit.
int tokenize_to(::llama_model* model, const char* text, bool add_bos,
                std::vector<::llama_token>& tokens) {
    const int text_len = static_cast<int>(std::strlen(text));
    const int n_guess  = std::max(64, text_len);
    tokens.resize(static_cast<std::size_t>(n_guess));
    int n = ::llama_tokenize(model, text, text_len,
                              tokens.data(), static_cast<int>(tokens.size()),
                              /*add_special=*/add_bos,
                              /*parse_special=*/true);
    if (n < 0) {
        tokens.resize(static_cast<std::size_t>(-n));
        n = ::llama_tokenize(model, text, text_len,
                              tokens.data(), static_cast<int>(tokens.size()),
                              add_bos, /*parse_special=*/true);
    }
    if (n < 0) return -1;
    tokens.resize(static_cast<std::size_t>(n));
    return n;
}

std::string token_to_string(::llama_model* model, ::llama_token tok) {
    std::string out;
    out.resize(64);
    int n = ::llama_token_to_piece(model, tok, out.data(),
                                    static_cast<int>(out.size()),
                                    /*lstrip=*/0, /*special=*/false);
    if (n < 0) {
        out.resize(static_cast<std::size_t>(-n));
        n = ::llama_token_to_piece(model, tok, out.data(),
                                    static_cast<int>(out.size()),
                                    /*lstrip=*/0, /*special=*/false);
    }
    if (n <= 0) return {};
    out.resize(static_cast<std::size_t>(n));
    return out;
}

// ---- Capability gate ------------------------------------------------------

constexpr std::array<ra_primitive_t, 2>       kPrimitives =
    { RA_PRIMITIVE_GENERATE_TEXT, RA_PRIMITIVE_EMBED };
constexpr std::array<ra_model_format_t, 1>    kFormats    = { RA_FORMAT_GGUF };
constexpr std::array<ra_runtime_id_t, 1>      kRuntimes   =
    { RA_RUNTIME_SELF_CONTAINED };

bool capability_check() {
    // llama.cpp supports every platform we ship on.
    return true;
}

// ---- LLM vtable ----------------------------------------------------------

ra_status_t llm_create(const ra_model_spec_t*     spec,
                        const ra_session_config_t* cfg,
                        ra_llm_session_t**         out) {
    if (!out) return RA_ERR_INVALID_ARGUMENT;
    ra_status_t st = RA_OK;
    auto* s = create_common_session(spec, cfg, /*for_embed=*/false, &st);
    if (!s) return st;
    *out = reinterpret_cast<ra_llm_session_t*>(s);
    return RA_OK;
}

void llm_destroy(ra_llm_session_t* session) {
    destroy_common_session(reinterpret_cast<LlamaSession*>(session));
}

ra_status_t llm_generate(ra_llm_session_t*   session,
                          const ra_prompt_t*  prompt,
                          ra_token_callback_t on_token,
                          ra_error_callback_t on_error,
                          void*               user_data) {
    auto* s = reinterpret_cast<LlamaSession*>(session);
    if (!s || !s->ctx || !s->model || !prompt || !prompt->text) {
        if (on_error) on_error(RA_ERR_INVALID_ARGUMENT, "bad arguments",
                                user_data);
        return RA_ERR_INVALID_ARGUMENT;
    }
    s->cancel_flag.store(false, std::memory_order_release);

    std::vector<::llama_token> prompt_tokens;
    if (tokenize_to(s->model, prompt->text, /*add_bos=*/true,
                     prompt_tokens) < 0) {
        if (on_error) on_error(RA_ERR_INTERNAL, "tokenize failed", user_data);
        return RA_ERR_INTERNAL;
    }
    if (prompt_tokens.empty()) {
        if (on_error) on_error(RA_ERR_INVALID_ARGUMENT,
                                "empty prompt after tokenization", user_data);
        return RA_ERR_INVALID_ARGUMENT;
    }
    if (static_cast<int>(prompt_tokens.size()) >= s->n_ctx) {
        if (on_error) on_error(RA_ERR_INVALID_ARGUMENT,
                                "prompt exceeds context size", user_data);
        return RA_ERR_INVALID_ARGUMENT;
    }

    // Seed the KV cache with the prompt in a single decode call.
    {
        ::llama_batch batch = ::llama_batch_get_one(
            prompt_tokens.data(),
            static_cast<int32_t>(prompt_tokens.size()));
        const int32_t rc = ::llama_decode(s->ctx, batch);
        if (rc != 0) {
            if (on_error) on_error(RA_ERR_INTERNAL, "prompt decode failed",
                                    user_data);
            return RA_ERR_INTERNAL;
        }
    }

    // Greedy decode loop. `last` holds the most recently sampled token so
    // we can feed it back into the context as the next decode input.
    int produced = 0;
    ::llama_token last = 0;
    while (produced < s->max_new_tokens) {
        if (s->cancel_flag.load(std::memory_order_acquire)) {
            if (on_token) {
                ra_token_output_t t{};
                t.text       = "";
                t.is_final   = 1;
                t.token_kind = 1;
                on_token(&t, user_data);
            }
            return RA_OK;
        }

        last = ::llama_sampler_sample(s->sampler, s->ctx, -1);
        if (::llama_token_is_eog(s->model, last)) {
            if (on_token) {
                ra_token_output_t t{};
                t.text       = "";
                t.is_final   = 1;
                t.token_kind = 1;
                on_token(&t, user_data);
            }
            return RA_OK;
        }

        std::string piece = token_to_string(s->model, last);
        if (on_token) {
            ra_token_output_t t{};
            t.text       = piece.c_str();
            t.is_final   = 0;
            t.token_kind = 1;
            on_token(&t, user_data);
        }
        ::llama_sampler_accept(s->sampler, last);

        ::llama_batch step = ::llama_batch_get_one(&last, 1);
        const int32_t rc = ::llama_decode(s->ctx, step);
        if (rc != 0) {
            if (on_error) on_error(RA_ERR_INTERNAL, "decode step failed",
                                    user_data);
            return RA_ERR_INTERNAL;
        }
        ++produced;
    }

    // Hit max_new_tokens. Emit a final empty marker so the consumer closes
    // the stream cleanly.
    if (on_token) {
        ra_token_output_t t{};
        t.text       = "";
        t.is_final   = 1;
        t.token_kind = 1;
        on_token(&t, user_data);
    }
    return RA_OK;
}

ra_status_t llm_cancel(ra_llm_session_t* session) {
    if (auto* s = reinterpret_cast<LlamaSession*>(session)) {
        s->cancel_flag.store(true, std::memory_order_release);
    }
    return RA_OK;
}

ra_status_t llm_reset(ra_llm_session_t* session) {
    auto* s = reinterpret_cast<LlamaSession*>(session);
    if (!s || !s->ctx) return RA_ERR_INVALID_ARGUMENT;
    // Clear the KV cache — starts a fresh conversation.
    ::llama_kv_cache_clear(s->ctx);
    // Reset the sampler chain too so repetition penalties don't carry
    // over between turns.
    if (s->sampler) ::llama_sampler_reset(s->sampler);
    return RA_OK;
}

// ---- Embed vtable --------------------------------------------------------

ra_status_t embed_create(const ra_model_spec_t*      spec,
                          const ra_session_config_t*  cfg,
                          ra_embed_session_t**        out) {
    if (!out) return RA_ERR_INVALID_ARGUMENT;
    ra_status_t st = RA_OK;
    auto* s = create_common_session(spec, cfg, /*for_embed=*/true, &st);
    if (!s) return st;
    *out = reinterpret_cast<ra_embed_session_t*>(s);
    return RA_OK;
}

void embed_destroy(ra_embed_session_t* session) {
    destroy_common_session(reinterpret_cast<LlamaSession*>(session));
}

int32_t embed_dims(ra_embed_session_t* session) {
    auto* s = reinterpret_cast<LlamaSession*>(session);
    if (!s || !s->model) return 0;
    return ::llama_n_embd(s->model);
}

ra_status_t embed_text(ra_embed_session_t* session,
                        const char*         text,
                        float*              out_vec,
                        int                 dims) {
    auto* s = reinterpret_cast<LlamaSession*>(session);
    if (!s || !s->ctx || !s->model || !text || !out_vec || dims <= 0) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    const int n_embd = ::llama_n_embd(s->model);
    if (dims < n_embd) return RA_ERR_INVALID_ARGUMENT;

    std::vector<::llama_token> tokens;
    if (tokenize_to(s->model, text, /*add_bos=*/true, tokens) < 0) {
        return RA_ERR_INTERNAL;
    }
    if (tokens.empty()) return RA_ERR_INVALID_ARGUMENT;

    ::llama_kv_cache_clear(s->ctx);

    ::llama_batch batch = ::llama_batch_get_one(
        tokens.data(), static_cast<int32_t>(tokens.size()));
    if (::llama_decode(s->ctx, batch) != 0) {
        return RA_ERR_INTERNAL;
    }

    const float* emb = ::llama_get_embeddings(s->ctx);
    if (!emb) {
        // Some model types expose per-sequence embeddings via _seq().
        emb = ::llama_get_embeddings_seq(s->ctx, /*seq_id=*/0);
    }
    if (!emb) return RA_ERR_INTERNAL;

    std::memcpy(out_vec, emb, sizeof(float) * static_cast<std::size_t>(n_embd));
    return RA_OK;
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(llamacpp) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "llamacpp";
    out_vtable->metadata.version           = "0.2.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();

    out_vtable->capability_check = &capability_check;

    out_vtable->llm_create   = &llm_create;
    out_vtable->llm_destroy  = &llm_destroy;
    out_vtable->llm_generate = &llm_generate;
    out_vtable->llm_cancel   = &llm_cancel;
    out_vtable->llm_reset    = &llm_reset;

    out_vtable->embed_create  = &embed_create;
    out_vtable->embed_destroy = &embed_destroy;
    out_vtable->embed_text    = &embed_text;
    out_vtable->embed_dims    = &embed_dims;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(llamacpp)
