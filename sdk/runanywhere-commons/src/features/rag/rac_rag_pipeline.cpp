/**
 * @file rac_rag_pipeline.cpp
 * @brief RAG Pipeline C API Implementation
 *
 * Provides two creation modes:
 *   - rac_rag_pipeline_create: takes pre-created LLM + Embeddings service handles
 *   - rac_rag_pipeline_create_standalone: creates services via the registry
 */

#include "rac/features/rag/rac_rag_pipeline.h"

#include "rag_backend.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <memory>
#include <nlohmann/json.hpp>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"

#define LOG_TAG "RAG.Pipeline"
// B-AK-17-003: dual-route via __android_log_print on Android — see
// rac_rag_jni.cpp / rac_embeddings_service.cpp for rationale.
#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...)                                            \
    do {                                                     \
        __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__); \
        RAC_LOG_INFO(LOG_TAG, __VA_ARGS__);                  \
    } while (0)
#define LOGE(...)                                            \
    do {                                                     \
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__); \
        RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__);                 \
    } while (0)
#else
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#endif

using namespace runanywhere::rag;

// =============================================================================
// PIPELINE HANDLE
// =============================================================================

struct rac_rag_pipeline {
    std::unique_ptr<RAGBackend> backend;
};

// =============================================================================
// HELPERS
// =============================================================================

static RAGBackendConfig build_backend_config(const rac_rag_pipeline_config_t* config) {
    RAGBackendConfig bc;
    if (!config)
        return bc;

    if (config->embedding_dimension > 0)
        bc.embedding_dimension = config->embedding_dimension;
    if (config->top_k > 0)
        bc.top_k = config->top_k;
    bc.similarity_threshold = config->similarity_threshold;
    if (config->max_context_tokens > 0)
        bc.max_context_tokens = config->max_context_tokens;
    if (config->chunk_size > 0)
        bc.chunk_size = config->chunk_size;
    bc.chunk_overlap = config->chunk_overlap;
    if (config->prompt_template)
        bc.prompt_template = config->prompt_template;

    return bc;
}

// =============================================================================
// PUBLIC API — Handle-based creation (Voice Agent pattern)
// =============================================================================

extern "C" {

rac_result_t rac_rag_pipeline_create(rac_handle_t llm_service, rac_handle_t embeddings_service,
                                     const rac_rag_pipeline_config_t* config,
                                     rac_rag_pipeline_t** out_pipeline) {
    if (!llm_service || !embeddings_service || !out_pipeline) {
        LOGE("Null pointer in rac_rag_pipeline_create");
        return RAC_ERROR_NULL_POINTER;
    }

    *out_pipeline = nullptr;

    try {
        auto bc = build_backend_config(config);

        auto pipeline = std::make_unique<rac_rag_pipeline>();
        pipeline->backend =
            std::make_unique<RAGBackend>(bc, llm_service, embeddings_service, false);

        if (!pipeline->backend->is_initialized()) {
            LOGE("RAG pipeline failed to initialize");
            return RAC_ERROR_INITIALIZATION_FAILED;
        }

        *out_pipeline = pipeline.release();
        LOGI("RAG pipeline created (handle-based)");
        return RAC_SUCCESS;

    } catch (const std::exception& e) {
        LOGE("Exception creating pipeline: %s", e.what());
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
}

// =============================================================================
// PUBLIC API — Standalone creation (creates services via registry)
// =============================================================================

rac_result_t rac_rag_pipeline_create_standalone(const rac_rag_config_t* config,
                                                rac_rag_pipeline_t** out_pipeline) {
    if (!config || !out_pipeline) {
        LOGE("Null pointer in rac_rag_pipeline_create_standalone");
        return RAC_ERROR_NULL_POINTER;
    }

    if (!config->embedding_model_path) {
        LOGE("Embedding model path required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_pipeline = nullptr;

    rac_handle_t embed_handle = nullptr;
    rac_handle_t llm_handle = nullptr;

    try {
        LOGI("create_standalone: embed_path=%s, llm_path=%s",
             config->embedding_model_path,
             config->llm_model_path ? config->llm_model_path : "(none)");
        // Create embeddings service via registry, forwarding any config JSON (e.g. vocab_path)
        rac_result_t result = rac_embeddings_create_with_config(
            config->embedding_model_path, config->embedding_config_json, &embed_handle);
        if (result != RAC_SUCCESS || !embed_handle) {
            LOGE("Failed to create embeddings service: %d (handle=%p)", result, embed_handle);
            return result != RAC_SUCCESS ? result : RAC_ERROR_INITIALIZATION_FAILED;
        }
        LOGI("create_standalone: embed_handle=%p", (void*)embed_handle);

        // Create LLM service via registry (optional — can be null for embed-only pipelines)
        if (config->llm_model_path) {
            result = rac_llm_create(config->llm_model_path, &llm_handle);
            if (result != RAC_SUCCESS || !llm_handle) {
                LOGE("Failed to create LLM service: %d (handle=%p)", result, llm_handle);
                rac_embeddings_destroy(embed_handle);
                return result != RAC_SUCCESS ? result : RAC_ERROR_INITIALIZATION_FAILED;
            }
            LOGI("create_standalone: llm_handle=%p", (void*)llm_handle);
        }

        // Build pipeline config from legacy config
        rac_rag_pipeline_config_t pc = rac_rag_pipeline_config_default();
        pc.embedding_dimension = config->embedding_dimension;
        pc.top_k = config->top_k;
        pc.similarity_threshold = config->similarity_threshold;
        pc.max_context_tokens = config->max_context_tokens;
        pc.chunk_size = config->chunk_size;
        pc.chunk_overlap = config->chunk_overlap;
        pc.prompt_template = config->prompt_template;

        auto bc = build_backend_config(&pc);

        auto pipeline = std::make_unique<rac_rag_pipeline>();
        pipeline->backend = std::make_unique<RAGBackend>(bc, llm_handle, embed_handle, true);

        if (!pipeline->backend->is_initialized()) {
            LOGE("RAG pipeline failed to initialize");
            // pipeline destructor will clean up services via RAGBackend (owns_services=true)
            return RAC_ERROR_INITIALIZATION_FAILED;
        }

        *out_pipeline = pipeline.release();
        LOGI("RAG pipeline created (standalone)");
        return RAC_SUCCESS;

    } catch (const std::exception& e) {
        LOGE("Exception creating standalone pipeline: %s", e.what());
        if (llm_handle)
            rac_llm_destroy(llm_handle);
        if (embed_handle)
            rac_embeddings_destroy(embed_handle);
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
}

// =============================================================================
// Document operations (unchanged)
// =============================================================================

rac_result_t rac_rag_add_document(rac_rag_pipeline_t* pipeline, const char* document_text,
                                  const char* metadata_json) {
    if (!pipeline || !document_text)
        return RAC_ERROR_NULL_POINTER;

    try {
        nlohmann::json metadata;
        if (metadata_json)
            metadata = nlohmann::json::parse(metadata_json);

        return pipeline->backend->add_document(document_text, metadata)
                   ? RAC_SUCCESS
                   : RAC_ERROR_PROCESSING_FAILED;
    } catch (const std::exception& e) {
        LOGE("Exception adding document: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

rac_result_t rac_rag_add_documents_batch(rac_rag_pipeline_t* pipeline, const char** documents,
                                         const char** metadata_array, size_t count) {
    if (!pipeline || !documents)
        return RAC_ERROR_NULL_POINTER;

    size_t failed_count = 0;
    for (size_t i = 0; i < count; ++i) {
        const char* metadata = metadata_array ? metadata_array[i] : nullptr;
        rac_result_t result = rac_rag_add_document(pipeline, documents[i], metadata);
        if (result != RAC_SUCCESS) {
            LOGE("Failed to add document %zu of %zu: %d", i, count, result);
            ++failed_count;
        }
    }

    if (failed_count == count && count > 0) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    return RAC_SUCCESS;
}

// =============================================================================
// Query — delegates to RAGBackend which runs a GraphScheduler-driven DAG
// =============================================================================
//
// Both rac_rag_query (blocking) and rac_rag_pipeline_query (streaming) share
// the same underlying graph; the only difference is whether the caller wants
// per-token notifications. We funnel through `run_query_internal` to keep the
// option-fill, metadata-extract, and result-population code in one place.

namespace {

rac_llm_options_t make_llm_options(const rac_rag_query_t* query) {
    rac_llm_options_t opts = {};
    opts.max_tokens = query->max_tokens > 0 ? query->max_tokens : 512;
    opts.temperature = query->temperature >= 0.0f ? query->temperature : 0.7f;
    opts.top_p = query->top_p >= 0.0f ? query->top_p : 0.9f;
    opts.system_prompt = query->system_prompt;
    return opts;
}

void populate_result_from_metadata(rac_rag_result_t* out_result,
                                   const rac_llm_result_t& llm_result,
                                   const nlohmann::json& metadata, double total_ms) {
    out_result->answer = llm_result.text ? rac_strdup(llm_result.text) : nullptr;
    out_result->num_chunks = 0;
    out_result->retrieved_chunks = nullptr;

    if (metadata.contains("context_used") && metadata["context_used"].is_string()) {
        out_result->context_used =
            rac_strdup(metadata["context_used"].get<std::string>().c_str());
    } else {
        out_result->context_used = nullptr;
    }

    if (metadata.contains("sources") && metadata["sources"].is_array()) {
        const auto& sources = metadata["sources"];
        size_t n = sources.size();
        if (n > 0) {
            out_result->retrieved_chunks =
                static_cast<rac_search_result_t*>(rac_alloc(sizeof(rac_search_result_t) * n));
            if (out_result->retrieved_chunks) {
                out_result->num_chunks = n;
                for (size_t i = 0; i < n; ++i) {
                    const auto& s = sources[i];
                    auto& c = out_result->retrieved_chunks[i];
                    c.chunk_id = rac_strdup(s["id"].get<std::string>().c_str());
                    c.similarity_score = s["score"].get<float>();
                    c.text = (s.contains("text") && s["text"].is_string())
                                 ? rac_strdup(s["text"].get<std::string>().c_str())
                                 : nullptr;
                    c.metadata_json = nullptr;
                    if (s.contains("source"))
                        c.metadata_json = rac_strdup(s["source"].get<std::string>().c_str());
                }
            }
        }
    }

    out_result->generation_time_ms = llm_result.total_time_ms;
    out_result->retrieval_time_ms = std::max(0.0, total_ms - llm_result.total_time_ms);
    out_result->total_time_ms = total_ms;
}

rac_result_t run_query_internal(rac_rag_pipeline_t* pipeline, const rac_rag_query_t* query,
                                std::function<bool(const std::string&)> on_token,
                                rac_rag_result_t* out_result) {
    if (!pipeline || !query) return RAC_ERROR_NULL_POINTER;
    if (!query->question) return RAC_ERROR_INVALID_ARGUMENT;

    try {
        rac_llm_options_t opts = make_llm_options(query);

        auto start = std::chrono::high_resolution_clock::now();
        rac_llm_result_t llm_result = {};
        nlohmann::json metadata;

        rac_result_t status = pipeline->backend->query(query->question, &opts, &llm_result,
                                                       metadata, std::move(on_token));

        auto end = std::chrono::high_resolution_clock::now();
        const double total_ms =
            std::chrono::duration<double, std::milli>(end - start).count();

        if (status != RAC_SUCCESS) {
            rac_llm_result_free(&llm_result);
            return status;
        }

        if (out_result) {
            populate_result_from_metadata(out_result, llm_result, metadata, total_ms);
        }

        rac_llm_result_free(&llm_result);
        return RAC_SUCCESS;

    } catch (const std::exception& e) {
        LOGE("Exception in RAG query: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

}  // namespace

rac_result_t rac_rag_query(rac_rag_pipeline_t* pipeline, const rac_rag_query_t* query,
                           rac_rag_result_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
    return run_query_internal(pipeline, query, /*on_token=*/nullptr, out_result);
}

rac_result_t rac_rag_pipeline_query(rac_rag_pipeline_t* pipeline, const rac_rag_query_t* query,
                                    rac_rag_token_callback_fn callback, void* user_data,
                                    rac_rag_result_t* out_result) {
    std::function<bool(const std::string&)> sink;
    if (callback) {
        sink = [callback, user_data](const std::string& token) -> bool {
            return callback(token.c_str(), user_data) == RAC_TRUE;
        };
    }
    return run_query_internal(pipeline, query, std::move(sink), out_result);
}

// =============================================================================
// Utility operations (unchanged)
// =============================================================================

rac_result_t rac_rag_clear_documents(rac_rag_pipeline_t* pipeline) {
    if (!pipeline)
        return RAC_ERROR_NULL_POINTER;
    pipeline->backend->clear();
    return RAC_SUCCESS;
}

size_t rac_rag_get_document_count(rac_rag_pipeline_t* pipeline) {
    if (!pipeline)
        return 0;
    return pipeline->backend->document_count();
}

rac_result_t rac_rag_get_statistics(rac_rag_pipeline_t* pipeline, char** out_stats_json) {
    if (!pipeline || !out_stats_json)
        return RAC_ERROR_NULL_POINTER;

    try {
        auto stats = pipeline->backend->get_statistics();
        std::string json_str = stats.dump();
        *out_stats_json = rac_strdup(json_str.c_str());
        return *out_stats_json ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        LOGE("Exception getting statistics: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

void rac_rag_result_free(rac_rag_result_t* result) {
    if (!result)
        return;

    rac_free(result->answer);
    rac_free(result->context_used);

    if (result->retrieved_chunks) {
        for (size_t i = 0; i < result->num_chunks; ++i) {
            rac_free(result->retrieved_chunks[i].chunk_id);
            rac_free(result->retrieved_chunks[i].text);
            rac_free(result->retrieved_chunks[i].metadata_json);
        }
        rac_free(result->retrieved_chunks);
    }

    memset(result, 0, sizeof(rac_rag_result_t));
}

void rac_rag_pipeline_destroy(rac_rag_pipeline_t* pipeline) {
    if (!pipeline)
        return;
    LOGI("Destroying RAG pipeline");
    delete pipeline;
}

}  // extern "C"
