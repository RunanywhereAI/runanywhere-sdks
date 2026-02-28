/**
 * @file vector_store_usearch.h
 * @brief Vector Store Implementation using USearch
 *
 * High-performance HNSW-based vector similarity search for edge devices.
 */

#ifndef RUNANYWHERE_VECTOR_STORE_USEARCH_H
#define RUNANYWHERE_VECTOR_STORE_USEARCH_H

#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <optional>
#include <algorithm>

#include <nlohmann/json.hpp>

namespace runanywhere {
namespace rag {

/**
 * @brief Document chunk stored in vector database
 */
struct DocumentChunk {
    std::string id;
    std::string text;
    std::vector<float> embedding;
    nlohmann::json metadata;
};

/**
 * @brief Search result with similarity score
 *
 * Note: id/chunk_id and score/similarity are aliases kept for backward
 * compatibility with JNI and React Native bridges. Prefer id and score.
 */
struct SearchResult {
    std::string id;           // Primary chunk identifier
    std::string chunk_id;     // Alias for id (kept for bridge compatibility)
    std::string text;         // Chunk text content
    float score = 0.0f;      // Primary similarity score (0.0-1.0)
    float similarity = 0.0f; // Alias for score (kept for bridge compatibility)
    nlohmann::json metadata;  // Additional metadata
};

/**
 * @brief Vector store configuration
 */
struct VectorStoreConfig {
    size_t dimension = 384;              // Embedding dimension
    size_t max_elements = 100000;        // Max capacity
    size_t connectivity = 16;            // HNSW connectivity (M)
    size_t expansion_add = 40;           // Construction search depth
    size_t expansion_search = 30;        // Query search depth
};

/**
 * @brief USearch-based vector store for efficient similarity search
 */
class VectorStoreUSearch {
public:
    explicit VectorStoreUSearch(const VectorStoreConfig& config);
    ~VectorStoreUSearch();

    // Disable copy
    VectorStoreUSearch(const VectorStoreUSearch&) = delete;
    VectorStoreUSearch& operator=(const VectorStoreUSearch&) = delete;

    /**
     * @brief Add a document chunk to the index
     */
    bool add_chunk(const DocumentChunk& chunk);

    /**
     * @brief Add multiple chunks in batch (more efficient)
     */
    bool add_chunks_batch(const std::vector<DocumentChunk>& chunks);

    /**
     * @brief Search for similar chunks
     *
     * @param query_embedding Query vector
     * @param top_k Number of results
     * @param threshold Minimum similarity (0.0-1.0)
     * @return Vector of search results sorted by similarity
     */
    std::vector<SearchResult> search(
        const std::vector<float>& query_embedding,
        size_t top_k,
        float threshold = 0.0f
    ) const noexcept;

    /**
     * @brief Look up a chunk by ID (text + metadata, no embedding)
     */
    std::optional<DocumentChunk> get_chunk(const std::string& chunk_id) const;

    /**
     * @brief Remove a chunk by ID
     */
    bool remove_chunk(const std::string& chunk_id);

    /**
     * @brief Clear all chunks
     */
    void clear();

    /**
     * @brief Get number of indexed chunks
     */
    size_t size() const;

    /**
     * @brief Get memory usage in bytes
     */
    size_t memory_usage() const;

    /**
     * @brief Get index statistics as JSON
     */
    nlohmann::json get_statistics() const;

    /**
     * @brief Save index to file
     */
    bool save(const std::string& path) const;

    /**
     * @brief Load index from file
     */
    bool load(const std::string& path);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
    mutable std::mutex mutex_;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_VECTOR_STORE_USEARCH_H
