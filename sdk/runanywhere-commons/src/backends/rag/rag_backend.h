/**
 * @file rag_backend.h
 * @brief RAG Backend Core
 */

#ifndef RUNANYWHERE_RAG_BACKEND_H
#define RUNANYWHERE_RAG_BACKEND_H

#include <memory>
#include <string>
#include <vector>
#include <mutex>

#include <nlohmann/json.hpp>

#include "vector_store_usearch.h"
#include "rag_chunker.h"
#include "inference_provider.h"

namespace runanywhere {
namespace rag {

/**
 * @brief RAG backend configuration
 */
struct RAGBackendConfig {
    size_t embedding_dimension = 384;
    size_t top_k = 3;
    float similarity_threshold = 0.3f;
    size_t max_context_tokens = 2048;
    size_t chunk_size = 512;
    size_t chunk_overlap = 50;
    std::string prompt_template = "Context:\n{context}\n\nQuestion: {query}\n\nAnswer:";
};

/**
 * @brief RAG backend coordinating vector store, embeddings, and generation
 * 
 * Uses strategy pattern with pluggable embedding and generation providers.
 * Thread-safe for all operations.
 */
class __attribute__((visibility("default"))) RAGBackend {
public:
    /**
     * @brief Construct RAG backend with configuration
     * 
     * @param config Backend configuration
     * @param embedding_provider Embedding provider (nullable, can be set later)
     * @param text_generator Text generator (nullable, can be set later)
     */
    explicit RAGBackend(
        const RAGBackendConfig& config,
        std::unique_ptr<IEmbeddingProvider> embedding_provider = nullptr,
        std::unique_ptr<ITextGenerator> text_generator = nullptr
    );
    
    ~RAGBackend();

    bool is_initialized() const { return initialized_; }

    /**
     * @brief Set embedding provider
     * 
     * @param provider Embedding provider to use
     */
    void set_embedding_provider(std::unique_ptr<IEmbeddingProvider> provider);

    /**
     * @brief Set text generator
     * 
     * @param generator Text generator to use
     */
    void set_text_generator(std::unique_ptr<ITextGenerator> generator);

    /**
     * @brief Add document to the index with automatic embedding
     * 
     * @param text Document text
     * @param metadata Optional metadata
     * @return true on success, false on failure
     * @throws std::runtime_error if embedding provider not set
     */
    bool add_document(
        const std::string& text,
        const nlohmann::json& metadata = {}
    );

    /**
     * @brief Search for relevant chunks using query text
     * 
     * @param query_text Query text to embed and search
     * @param top_k Number of results to return
     * @return Search results sorted by similarity
     * @throws std::runtime_error if embedding provider not set
     */
    std::vector<SearchResult> search(
        const std::string& query_text,
        size_t top_k
    ) const;

    /**
     * @brief Query RAG pipeline end-to-end
     * 
     * Embeds query, searches, builds context, and generates answer.
     * 
     * @param query User question
     * @param options Generation options
     * @return Generation result with answer and metadata
     * @throws std::runtime_error if providers not set
     */
    GenerationResult query(
        const std::string& query,
        const GenerationOptions& options = GenerationOptions{}
    );

    /**
     * @brief Build context from search results
     */
    std::string build_context(const std::vector<SearchResult>& results) const;

    /**
     * @brief Format prompt with context and query
     */
    std::string format_prompt(
        const std::string& query,
        const std::string& context
    ) const;

    /**
     * @brief Clear all documents
     */
    void clear();

    /**
     * @brief Get statistics
     */
    nlohmann::json get_statistics() const;

    size_t document_count() const;

private:
    std::vector<SearchResult> search_with_provider(
        const std::string& query_text,
        size_t top_k,
        const std::shared_ptr<IEmbeddingProvider>& embedding_provider,
        size_t embedding_dimension,
        float similarity_threshold,
        bool initialized
    ) const;

    RAGBackendConfig config_;
    std::unique_ptr<VectorStoreUSearch> vector_store_;
    std::unique_ptr<DocumentChunker> chunker_;
    std::shared_ptr<IEmbeddingProvider> embedding_provider_;
    std::shared_ptr<ITextGenerator> text_generator_;
    bool initialized_ = false;
    mutable std::mutex mutex_;
    size_t next_chunk_id_ = 0;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_RAG_BACKEND_H
