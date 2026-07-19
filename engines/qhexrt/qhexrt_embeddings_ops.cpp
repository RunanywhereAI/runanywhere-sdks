/**
 * @file qhexrt_embeddings_ops.cpp
 * @brief Embeddings (RAC_PRIMITIVE_EMBED) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in routable builds. Maps `rac_embeddings_service_ops_t` onto
 * `qhx_generate` with a text input: the QHexRT embedding-family plan runs the
 * encoder + pooling host-op and returns an L2-normalized sentence vector in
 * `qhx_output.embedding` / `n_embedding`. This adapter copies that vector into the
 * RAC embeddings result (one `rac_embedding_vector_t` per input text). Mirrors the
 * STT/LLM adapters (session_open -> qhx_generate -> fill result). No chat template
 * is applied (embedding inputs are raw text).
 */

#include "qhexrt_session.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) {
    return static_cast<Session*>(impl);
}

// qhx_generate wants a token callback even though the embedding plan emits no
// tokens; a trivial "keep going" callback keeps the signature happy.
int embed_noop_cb(void* /*user*/, const char* /*utf8*/, int /*len*/, int /*token_id*/,
                  int /*is_final*/) {
    return 1;
}

// Runs the encoder once over `text` and copies the L2-normalized sentence vector into a freshly
// malloc'd rac_embedding_vector_t (the RAC contract owns + frees result->embeddings[*].data).
rac_result_t embed_one(Session* c, const char* text, rac_embedding_vector_t* out_vec,
                       int64_t* out_ms, int* out_tokens) {
    qhx_session_reset(c->sess);  // each public embed() call is an independent request
    c->cancel.store(false, std::memory_order_relaxed);
    qhx_inputs in{};
    const char* t = (text != nullptr) ? text : "";
    in.text = t;
    in.no_template = 1;  // embedding inputs are raw text, never chat-templated
    qhx_gen_cfg cfg;
    qhx_gen_cfg_default(&cfg);
    qhx_output out{};
    qhx_status st = qhx_generate(c->sess, &in, &cfg, embed_noop_cb, nullptr, &out);
    if (st != 0) {
        RAC_LOG_ERROR(LOG_CAT, "qhx_generate(embed) failed: %s", qhx_status_str(st));
        return RAC_ERROR_GENERATION_FAILED;
    }
    if (out.embedding == nullptr || out.n_embedding <= 0) {
        RAC_LOG_ERROR(LOG_CAT, "qhx_generate(embed) produced no embedding vector");
        return RAC_ERROR_GENERATION_FAILED;
    }
    const size_t dim = static_cast<size_t>(out.n_embedding);
    auto* data = static_cast<float*>(malloc(dim * sizeof(float)));
    if (data == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(data, out.embedding, dim * sizeof(float));
    out_vec->data = data;
    out_vec->dimension = dim;
    if (out_ms != nullptr) {
        *out_ms = static_cast<int64_t>(out.prefill_ms + out.decode_ms);
    }
    if (out_tokens != nullptr) {
        *out_tokens = out.n_prompt;
    }
    return RAC_SUCCESS;
}

// ───────────────────────────────── vtable ops ───────────────────────────────

rac_result_t qhexrt_embeddings_create(const char* model_id, const char* /*config_json*/,
                                      void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_embeddings_create: manifest=%s", model_id);
    Session* s = session_open(model_id);
    if (s == nullptr) {
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }
    *out_impl = s;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_embeddings_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}

rac_result_t qhexrt_embeddings_embed(void* impl, const char* text,
                                     const rac_embeddings_options_t* /*options*/,
                                     rac_embeddings_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        *out_result = rac_embeddings_result_t{};
        auto* vec = static_cast<rac_embedding_vector_t*>(malloc(sizeof(rac_embedding_vector_t)));
        if (vec == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        *vec = rac_embedding_vector_t{};
        int64_t ms = 0;
        int tokens = 0;
        rac_result_t r = embed_one(c, text, &vec[0], &ms, &tokens);
        if (r != RAC_SUCCESS) {
            free(vec);
            return r;
        }
        out_result->embeddings = vec;
        out_result->num_embeddings = 1;
        out_result->dimension = vec[0].dimension;
        out_result->processing_time_ms = ms;
        out_result->total_tokens = tokens;
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_embeddings_embed_batch(void* impl, const char* const* texts, size_t num_texts,
                                           const rac_embeddings_options_t* /*options*/,
                                           rac_embeddings_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || out_result == nullptr || texts == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (num_texts == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    try {
        // Keep the whole batch atomic with respect to other operations on this
        // QHexRT session; embed_one deliberately does not acquire recursively.
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        *out_result = rac_embeddings_result_t{};
        auto* vecs =
            static_cast<rac_embedding_vector_t*>(calloc(num_texts, sizeof(rac_embedding_vector_t)));
        if (vecs == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        int64_t total_ms = 0;
        int total_tokens = 0;
        size_t dim = 0;
        for (size_t i = 0; i < num_texts; ++i) {
            int64_t ms = 0;
            int tokens = 0;
            rac_result_t r = embed_one(c, texts[i], &vecs[i], &ms, &tokens);
            if (r != RAC_SUCCESS) {
                for (size_t j = 0; j < i; ++j) {
                    free(vecs[j].data);
                }
                free(vecs);
                return r;
            }
            total_ms += ms;
            total_tokens += tokens;
            dim = vecs[i].dimension;
        }
        out_result->embeddings = vecs;
        out_result->num_embeddings = num_texts;
        out_result->dimension = dim;
        out_result->processing_time_ms = total_ms;
        out_result->total_tokens = total_tokens;
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_embeddings_get_info(void* impl, rac_embeddings_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* c = as_session(impl);
    *out_info = rac_embeddings_info_t{};
    if (c != nullptr) {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        out_info->is_ready = c->sess != nullptr ? RAC_TRUE : RAC_FALSE;
    }
    out_info->current_model = nullptr;
    out_info->dimension = 0;  // resolved per-model at embed time (from qhx_output.n_embedding)
    return RAC_SUCCESS;
}

rac_result_t qhexrt_embeddings_cleanup(void* impl) {
    auto* c = as_session(impl);
    if (c == nullptr) {
        return RAC_SUCCESS;
    }
    std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
    if (c->sess != nullptr) {
        qhx_session_reset(c->sess);
    }
    return RAC_SUCCESS;
}

void qhexrt_embeddings_destroy(void* impl) {
    session_close(as_session(impl));
}

}  // namespace

extern "C" const rac_embeddings_service_ops_t g_qhexrt_embeddings_ops = {
    /* .initialize  = */ qhexrt_embeddings_initialize,
    /* .embed       = */ qhexrt_embeddings_embed,
    /* .embed_batch = */ qhexrt_embeddings_embed_batch,
    /* .get_info    = */ qhexrt_embeddings_get_info,
    /* .cleanup     = */ qhexrt_embeddings_cleanup,
    /* .destroy     = */ qhexrt_embeddings_destroy,
    /* .create      = */ qhexrt_embeddings_create,
};
