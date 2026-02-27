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

#include <memory>
#include <string>
#include <vector>
#include <mutex>

#include <nlohmann/json.hpp>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

#include "vector_store_usearch.h"
#include "rag_chunker.h"
#include "bm25_index.h"

namespace runanywhere {
namespace rag {

struct RAGBackendConfig {
    size_t embedding_dimension = 384;
    size_t top_k = 10;
    float similarity_threshold = 0.15f;
    size_t max_context_tokens = 2048;
    size_t chunk_size = 180;
    size_t chunk_overlap = 30;
    std::string prompt_template = "Context:\n{context}\n\nQuestion: {query}\n\nAnswer:";
};

/**
 * @brief RAG pipeline orchestrator using service handles
 *
 * Coordinates vector store, embeddings service, and LLM service for
 * retrieval-augmented generation. Thread-safe for all operations.
 */
class __attribute__((visibility("default"))) RAGBackend {
public:
    /**
     * @brief Construct RAG pipeline with service handles
     *
     * @param config Pipeline configuration
     * @param llm_service Handle to LLM service (from rac_llm_create)
     * @param embeddings_service Handle to embeddings service (from rac_embeddings_create)
     * @param owns_services If true, pipeline will destroy services on cleanup
     */
    explicit RAGBackend(
        const RAGBackendConfig& config,
        rac_handle_t llm_service,
        rac_handle_t embeddings_service,
        bool owns_services
    );

    ~RAGBackend();

    RAGBackend(const RAGBackend&) = delete;
    RAGBackend& operator=(const RAGBackend&) = delete;

    bool is_initialized() const { return initialized_; }

    bool add_document(const std::string& text, const nlohmann::json& metadata = {});

    std::vector<SearchResult> search(const std::string& query_text, size_t top_k) const;

    /**
     * @brief End-to-end RAG query with adaptive context accumulation
     */
    rac_result_t query(
        const std::string& question,
        const rac_llm_options_t* options,
        rac_llm_result_t* out_result,
        nlohmann::json& out_metadata
    );

    std::string build_context(const std::vector<SearchResult>& results) const;
    std::string format_prompt(const std::string& query, const std::string& context) const;

    void clear();
    nlohmann::json get_statistics() const;
    size_t document_count() const;

private:
    std::vector<float> embed_text(const std::string& text) const;
    std::vector<std::vector<float>> embed_texts_batch(const std::vector<std::string>& texts) const;

    std::vector<SearchResult> search_with_embedding(
        const std::string& query_text,
        size_t top_k,
        size_t embedding_dimension,
        float similarity_threshold
    ) const;

    std::vector<SearchResult> fuse_results(
        const std::vector<SearchResult>& dense_results,
        const std::vector<std::pair<std::string, float>>& bm25_results,
        size_t top_k
    ) const;

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
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_RAG_BACKEND_H
