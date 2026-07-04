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
    // Fallback only: when the caller omits embedding_dimension, the RAG proto
    // ABI derives it from the loaded embedding model (rac_embeddings_get_info)
    // at session create. 384 applies only if that derivation fails.
    size_t embedding_dimension = 384;
    size_t top_k = 5;
    // 0.0 (accept-everything) — MiniLM-class cosine similarities rarely exceed
    // ~0.5 for relevant chunks, so any positive floor risks returning nothing;
    // retrieval relies on top_k for relevance (matches idl/rag.proto).
    float similarity_threshold = 0.0f;
    size_t max_context_tokens = 2048;
    size_t chunk_size = 512;
    size_t chunk_overlap = 64;
    std::string prompt_template = "Context:\n{context}\n\nQuestion: {query}\n\nAnswer:";
    // When true, fused retrieval candidates are reranked by LLM-pointwise
    // relevance scoring before context assembly (RAGConfiguration.rerank_results).
    bool rerank = false;

    // Persistence (RAGConfiguration.index_path / persist_index). When persist
    // is true and index_path is set, the index is snapshotted after every
    // ingest and reloaded (fingerprint-guarded) at session create so a restart
    // never re-embeds the corpus. embedding_model_id feeds the fingerprint.
    bool persist_index = false;
    std::string index_path;
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

    void clear();
    nlohmann::json get_statistics() const;
    size_t document_count() const;

    /**
     * @brief Load a fingerprint-guarded index snapshot from config_.index_path
     * via the platform adapter. Rebuilds the BM25 index from the restored
     * chunks. No-op (returns false) when persistence is disabled, the file is
     * absent, or the fingerprint (embedding model + dim + format version) does
     * not match — in which case the caller proceeds with an empty index and
     * re-embeds on ingest.
     */
    bool load_index();

    /**
     * @brief Serialize the current index to config_.index_path via the platform
     * adapter, prefixed with the fingerprint. No-op when persistence is off.
     */
    bool save_index() const;

    /** Remove the on-disk snapshot (explicit clear only, not on teardown). */
    void delete_snapshot() const;

   private:
    std::string index_fingerprint() const;


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
    size_t next_chunk_id_ = 0;

    // Content-addressed dedup: sha256 of the normalized document text for every
    // ingested doc. A re-ingest of the same input is skipped (no re-chunk, no
    // re-embed). Rebuilt from restored chunk metadata on load_index().
    std::unordered_set<std::string> ingested_content_hashes_;
};

}  // namespace rag
}  // namespace runanywhere

#endif  // RUNANYWHERE_RAG_BACKEND_H
