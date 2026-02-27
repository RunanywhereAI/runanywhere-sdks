/**
 * @file bm25_index.h
 * @brief BM25 Sparse Keyword Search Index for Hybrid RAG
 *
 * Lightweight BM25 index that runs alongside dense vector search
 * to improve retrieval of exact keywords, acronyms, IDs, and rare terms.
 * No persistence — rebuilt from vector store chunks on load.
 */

#ifndef RUNANYWHERE_BM25_INDEX_H
#define RUNANYWHERE_BM25_INDEX_H

#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace runanywhere {
namespace rag {

class BM25Index {
public:
    void add_chunk(const std::string& chunk_id, const std::string& text);
    void add_chunks_batch(const std::vector<std::pair<std::string, std::string>>& chunks);
    void remove_chunk(const std::string& chunk_id);
    void clear();
    size_t size() const;

    /// Returns (chunk_id, bm25_score) sorted descending by score
    std::vector<std::pair<std::string, float>> search(const std::string& query, size_t top_k) const;

private:
    static constexpr float k1_ = 1.2f;
    static constexpr float b_ = 0.75f;

    std::vector<std::string> tokenize(const std::string& text) const;

    // term -> [chunk_ids that contain term]
    std::unordered_map<std::string, std::vector<std::string>> inverted_index_;
    // chunk_id -> { term -> frequency }
    std::unordered_map<std::string, std::unordered_map<std::string, size_t>> chunk_term_freqs_;
    // chunk_id -> token count
    std::unordered_map<std::string, size_t> chunk_lengths_;
    size_t total_chunks_ = 0;
    size_t total_length_ = 0;
    double avg_chunk_length_ = 0.0;
    mutable std::mutex mutex_;
};

} // namespace rag
} // namespace runanywhere

#endif // RUNANYWHERE_BM25_INDEX_H
