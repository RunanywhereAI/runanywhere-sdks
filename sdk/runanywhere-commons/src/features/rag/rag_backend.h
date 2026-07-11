/**
 * @file rag_backend.h
 * @brief RAG Pipeline Core — Orchestrates LLM + Embeddings services
 *
 * Follows the Voice Agent pattern: takes pre-created service handles
 * and orchestrates them for RAG (chunking, embedding, vector search,
 * adaptive context accumulation, generation).
 */

#ifndef RUNANYWHERE_RAG_BACKEND_H
#define RUNANYWHERE_RAG_BACKEND_H

#include "bm25_index.h"
#include "rag_chunker.h"
#include "vector_store_usearch.h"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <unordered_set>
#include <string>
#include <vector>

#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"

namespace runanywhere {
namespace rag {

struct RAGBackendConfig {
    // Canonical defaults mirrored from idl/rag.proto `rac_default` annotations
    // (see also Swift RARAGConfiguration.defaults()). These in-struct defaults
    // are what `build_backend_config` (rac_rag_proto_abi.cpp) applies when a
    // caller passes a partial RAGConfiguration (proto zeros), so every platform
    // SDK ends up with the same chunk/retrieval behavior. Keep these in sync
    // with the IDL.
    // Zero means "auto". The proto ABI first asks the loaded embedding service
    // for its dimension; providers that cannot report it until inference (for
    // example QHexRT) leave this unresolved and RAG binds the vector store to
    // the first actual embedding output. A caller-supplied non-zero dimension
    // remains an explicit contract and is validated against model output.
    size_t embedding_dimension = 0;
    size_t top_k = 5;
    // 0.0 (accept-everything) — MiniLM-class cosine similarities rarely exceed
    // ~0.5, and chunking lowers per-chunk similarity, so any positive floor
    // filters out real matches (multi-chunk docs return nothing). top_k bounds
    // the result count instead (matches idl/rag.proto).
    float similarity_threshold = 0.0f;
    size_t max_context_tokens = 2048;
    size_t chunk_size = 512;
    size_t chunk_overlap = 64;
    std::string prompt_template = "Context:\n{context}\n\nQuestion: {query}\n\nAnswer:";
    // When true, fused retrieval candidates are reranked by LLM-pointwise
    // relevance scoring before context assembly (RAGConfiguration.rerank_results).
    bool rerank = false;

    std::string embedding_model_id;
};

/**
 * @brief RAG pipeline orchestrator using service handles
 *
 * Coordinates vector store, embeddings service, and LLM service for
 * retrieval-augmented generation. Thread-safe for all operations.
 */
// RAGBackend is an internal implementation class — it is only referenced from
// translation units inside this library and is never exposed through a public
// header. No visibility attribute is needed (and asymmetric visibility on
// non-MSVC vs MSVC previously caused inconsistent ABI behavior).
class RAGBackend {
   public:
    /**
     * @brief Construct RAG pipeline with service handles
     *
     * @param config Pipeline configuration
     * @param llm_service Handle to LLM service (from rac_llm_create)
     * @param embeddings_service Handle to embeddings service (from rac_embeddings_create)
     * @param owns_services If true, pipeline will destroy services on cleanup
     */
    explicit RAGBackend(const RAGBackendConfig& config, rac_handle_t llm_service,
                        rac_handle_t embeddings_service, bool owns_services);

    ~RAGBackend();

    RAGBackend(const RAGBackend&) = delete;
    RAGBackend& operator=(const RAGBackend&) = delete;

    bool is_initialized() const { return initialized_; }

    bool add_document(const std::string& text, const nlohmann::json& metadata = {});

    std::vector<SearchResult> search(const std::string& query_text, size_t top_k) const;

    /**
     * @brief End-to-end RAG query.
     *
     * This method constructs a per-call GraphScheduler-driven
     * DAG (Embed → Retrieve → ContextAssembly → LLM) via `run_rag_query()`
     * instead of running the steps imperatively. When `on_token` is non-null,
     * tokens are forwarded as the LLM streams them.
     */
    /**
     * Per-query retrieval overrides taken from RAGQueryOptions
     * (idl/rag.proto). A zero/unset value falls back to the session-level
     * `RAGConfig` defaults (top_k, similarity_threshold).
     */
    struct QueryOverrides {
        int32_t retrieval_top_k = 0;
        // has_similarity_threshold distinguishes an explicit floor (incl. 0.0 =
        // accept everything) from "unset" (fall back to the session default).
        bool has_similarity_threshold = false;
        float similarity_threshold = 0.0f;
        // Multi-query expansion (RAGQueryOptions.enable_multi_query).
        bool enable_multi_query = false;
        int32_t multi_query_count = 0;  // 0 = use default
        // Scoped retrieval: only chunks whose document_id starts with this
        // prefix are eligible. Empty = whole index.
        std::string scope_prefix;
    };

    rac_result_t query(const std::string& question, const rac_llm_options_t* options,
                       rac_llm_result_t* out_result, nlohmann::json& out_metadata,
                       std::function<bool(const std::string&)> on_token = nullptr,
                       const QueryOverrides* overrides = nullptr);

    /** Request cancellation without taking the corpus mutex. */
    rac_result_t cancel_query();

    void clear();
    nlohmann::json get_statistics() const;
    size_t document_count() const;

   private:
    // Must be called with mutex_ held. Initializes the vector store on the
    // first real embedding when the provider could not report its dimension at
    // session creation, or validates an explicit/previously resolved value.
    bool ensure_embedding_dimension_locked(size_t actual_dimension);

    std::vector<float> embed_text(const std::string& text) const;
    std::vector<std::vector<float>> embed_texts_batch(const std::vector<std::string>& texts) const;

    std::vector<SearchResult> search_with_embedding(const std::string& query_text, size_t top_k,
                                                    size_t embedding_dimension,
                                                    float similarity_threshold) const;

    std::vector<SearchResult>
    fuse_results(const std::vector<SearchResult>& dense_results,
                 const std::vector<std::pair<std::string, float>>& bm25_results,
                 size_t top_k) const;

    RAGBackendConfig config_;
    std::unique_ptr<VectorStoreUSearch> vector_store_;
    std::unique_ptr<BM25Index> bm25_index_;
    std::unique_ptr<DocumentChunker> chunker_;

    rac_handle_t llm_service_;
    rac_handle_t embeddings_service_;
    bool owns_services_;

    bool initialized_ = false;
    mutable std::mutex mutex_;
    // Each query owns a fresh cancellation token. Publishing/removing the
    // shared token under a dedicated mutex avoids both failure modes of the
    // old process-wide bool: an early cancel cannot be cleared by query entry,
    // and a completed query cannot poison its successor.
    mutable std::mutex query_state_mutex_;
    std::shared_ptr<std::atomic<bool>> active_query_cancel_;
    size_t next_chunk_id_ = 0;

    // Content-addressed dedup: sha256 of the normalized document text for every
    // ingested doc. A re-ingest of the same input is skipped (no re-chunk, no
    // re-embed). In-memory only — lives for the session, gone on teardown.
    std::unordered_set<std::string> ingested_content_hashes_;
};

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_RAG_BACKEND_H
