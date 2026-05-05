/**
 * @file rac_onnx_embeddings_register.cpp
 * @brief ONNX Embeddings Backend Registration
 *
 * Wraps the existing ONNXEmbeddingProvider in the standard rac_embeddings_service_ops_t
 * vtable and registers with the service registry for RAC_CAPABILITY_EMBEDDINGS.
 */

#include "onnx_embedding_provider.h"

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "rac/backends/rac_embeddings_onnx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

static const char* LOG_CAT = "Embeddings.ONNX";

// =============================================================================
// INTERNAL HANDLE
// =============================================================================

struct onnx_embeddings_handle {
    std::unique_ptr<runanywhere::rag::ONNXEmbeddingProvider> provider;
};

// =============================================================================
// VTABLE IMPLEMENTATION
// =============================================================================

namespace {

static rac_result_t onnx_embed_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

static rac_result_t onnx_embed_vtable_embed(void* impl, const char* text,
                                            const rac_embeddings_options_t* options,
                                            rac_embeddings_result_t* out_result) {
    (void)options;
    if (!impl || !text || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* h = static_cast<onnx_embeddings_handle*>(impl);
    if (!h->provider || !h->provider->is_ready())
        return RAC_ERROR_BACKEND_NOT_READY;

    try {
        auto embedding = h->provider->embed(text);
        size_t dim = embedding.size();

        out_result->num_embeddings = 1;
        out_result->dimension = dim;
        out_result->processing_time_ms = 0;
        out_result->total_tokens = 0;

        out_result->embeddings =
            static_cast<rac_embedding_vector_t*>(malloc(sizeof(rac_embedding_vector_t)));
        if (!out_result->embeddings)
            return RAC_ERROR_OUT_OF_MEMORY;

        out_result->embeddings[0].dimension = dim;
        out_result->embeddings[0].data = static_cast<float*>(malloc(dim * sizeof(float)));
        if (!out_result->embeddings[0].data) {
            free(out_result->embeddings);
            out_result->embeddings = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        memcpy(out_result->embeddings[0].data, embedding.data(), dim * sizeof(float));
        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Embedding failed: %s", e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

static rac_result_t onnx_embed_vtable_embed_batch(void* impl, const char* const* texts,
                                                  size_t num_texts,
                                                  const rac_embeddings_options_t* options,
                                                  rac_embeddings_result_t* out_result) {
    (void)options;
    if (!impl || !texts || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* h = static_cast<onnx_embeddings_handle*>(impl);
    if (!h->provider || !h->provider->is_ready())
        return RAC_ERROR_BACKEND_NOT_READY;

    try {
        std::vector<std::string> texts_vec;
        texts_vec.reserve(num_texts);
        for (size_t i = 0; i < num_texts; ++i) {
            texts_vec.emplace_back(texts[i]);
        }

        auto batch_results = h->provider->embed_batch(texts_vec);
        if (batch_results.size() != num_texts) {
            RAC_LOG_ERROR(LOG_CAT, "Batch embedding returned %zu results, expected %zu",
                          batch_results.size(), num_texts);
            return RAC_ERROR_INFERENCE_FAILED;
        }

        size_t dim = h->provider->dimension();
        out_result->num_embeddings = num_texts;
        out_result->dimension = dim;
        out_result->processing_time_ms = 0;
        out_result->total_tokens = 0;

        out_result->embeddings =
            static_cast<rac_embedding_vector_t*>(calloc(num_texts, sizeof(rac_embedding_vector_t)));
        if (!out_result->embeddings)
            return RAC_ERROR_OUT_OF_MEMORY;

        for (size_t i = 0; i < num_texts; ++i) {
            const auto& embedding = batch_results[i];
            out_result->embeddings[i].dimension = embedding.size();
            out_result->embeddings[i].data =
                static_cast<float*>(malloc(embedding.size() * sizeof(float)));
            if (!out_result->embeddings[i].data) {
                rac_embeddings_result_free(out_result);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            memcpy(out_result->embeddings[i].data, embedding.data(),
                   embedding.size() * sizeof(float));
        }

        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Batch embedding failed: %s", e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

static rac_result_t onnx_embed_vtable_get_info(void* impl, rac_embeddings_info_t* out_info) {
    if (!impl || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* h = static_cast<onnx_embeddings_handle*>(impl);
    out_info->is_ready = (h->provider && h->provider->is_ready()) ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = h->provider ? h->provider->name() : nullptr;
    out_info->dimension = h->provider ? h->provider->dimension() : 0;
    out_info->max_tokens = 512;

    return RAC_SUCCESS;
}

static rac_result_t onnx_embed_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

static void onnx_embed_vtable_destroy(void* impl) {
    if (impl) {
        delete static_cast<onnx_embeddings_handle*>(impl);
    }
}

// v3 Phase B7: ONNX embeddings `create` adapter. Allocates an
// onnx_embeddings_handle wrapping ONNXEmbeddingProvider. Called by
// commons rac_embeddings_create() via rac_plugin_route → g_onnx_engine_vtable
// (embedding_ops slot).
static rac_result_t onnx_embed_create_impl(const char* model_id,
                                           const char* config_json,
                                           void** out_impl) {
    if (!model_id || !out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "onnx_embed_create_impl: model=%s", model_id);
    try {
        auto handle = std::make_unique<onnx_embeddings_handle>();
        const char* cfg = (config_json && config_json[0] != '\0') ? config_json : "";
        handle->provider =
            std::make_unique<runanywhere::rag::ONNXEmbeddingProvider>(model_id, cfg);
        if (!handle->provider->is_ready()) {
            RAC_LOG_ERROR(LOG_CAT, "ONNX embedding provider not ready after init");
            return RAC_ERROR_BACKEND_NOT_READY;
        }
        RAC_LOG_INFO(LOG_CAT, "ONNX embeddings backend created (dim=%zu)",
                     handle->provider->dimension());
        *out_impl = handle.release();
        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create ONNX embeddings: %s", e.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

}  // namespace

// Exposed non-static so rac_plugin_entry_onnx.cpp can extern-reference it
// to fill the unified g_onnx_engine_vtable.embedding_ops slot. Follows
// the same pattern as g_onnx_{stt,tts,vad}_ops in the sibling
// engines/onnx/rac_backend_onnx_register.cpp.
extern "C" const rac_embeddings_service_ops_t g_onnx_embeddings_ops = {
    .initialize = onnx_embed_vtable_initialize,
    .embed = onnx_embed_vtable_embed,
    .embed_batch = onnx_embed_vtable_embed_batch,
    .get_info = onnx_embed_vtable_get_info,
    .cleanup = onnx_embed_vtable_cleanup,
    .destroy = onnx_embed_vtable_destroy,
    .create = onnx_embed_create_impl,
};

namespace {

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct OnnxEmbeddingsRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "ONNXEmbeddings";
    char module_id[24] = "onnx_embeddings";
};

OnnxEmbeddingsRegistryState& get_onnx_embed_state() {
    static OnnxEmbeddingsRegistryState state;
    return state;
}

// v3 Phase B7: legacy rac_service_request_t factories removed.
// Model-format gating (.onnx / directory containing model.onnx /
// RAC_FRAMEWORK_ONNX) lives in g_onnx_engine_vtable.metadata.formats
// in engines/onnx/rac_plugin_entry_onnx.cpp. Backend impl allocation
// goes through g_onnx_embeddings_ops.create (onnx_embed_create_impl
// defined above).

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_onnx_embeddings_register(void) {
    auto& state = get_onnx_embed_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered)
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;

    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "ONNX Embeddings";
    module_info.version = "1.0.0";
    module_info.description = "Sentence-transformer embedding provider via ONNX Runtime";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_EMBEDDINGS};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED)
        return result;

    // v3 Phase B7: embeddings plugin registration flows through the
    // unified g_onnx_engine_vtable (embedding_ops slot) in
    // rac_plugin_entry_onnx.cpp.
    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "ONNX embeddings backend registered (module_register only; "
                          "plugin registration via rac_plugin_entry_onnx)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_embeddings_unregister(void) {
    auto& state = get_onnx_embed_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered)
        return RAC_ERROR_MODULE_NOT_FOUND;

    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "ONNX embeddings backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
