/**
 * @file bm25_index.cpp
 * @brief BM25 Sparse Keyword Search Index Implementation
 */

#include "bm25_index.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.BM25"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

// =============================================================================
// Tokenizer — split on whitespace, strip leading/trailing punctuation, lowercase
// Preserves compound tokens: "v2.15.2", "user_id", "192.168.1.1"
// =============================================================================

std::vector<std::string> BM25Index::tokenize(const std::string& text) const {
    std::vector<std::string> tokens;

    size_t i = 0;
    while (i < text.size()) {
        // Skip whitespace
        while (i < text.size() && std::isspace(static_cast<unsigned char>(text[i]))) {
            ++i;
        }
        if (i >= text.size()) break;

        // Collect non-whitespace run
        size_t start = i;
        while (i < text.size() && !std::isspace(static_cast<unsigned char>(text[i]))) {
            ++i;
        }

        // Strip leading punctuation
        size_t tok_start = start;
        while (tok_start < i && std::ispunct(static_cast<unsigned char>(text[tok_start]))) {
            ++tok_start;
        }

        // Strip trailing punctuation
        size_t tok_end = i;
        while (tok_end > tok_start && std::ispunct(static_cast<unsigned char>(text[tok_end - 1]))) {
            --tok_end;
        }

        if (tok_start >= tok_end) continue;

        // Lowercase
        std::string token;
        token.reserve(tok_end - tok_start);
        for (size_t j = tok_start; j < tok_end; ++j) {
            token.push_back(static_cast<char>(
                std::tolower(static_cast<unsigned char>(text[j]))));
        }

        tokens.push_back(std::move(token));
    }

    return tokens;
}

// =============================================================================
// Add / Remove
// =============================================================================

void BM25Index::add_chunk(const std::string& chunk_id, const std::string& text) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (chunk_term_freqs_.count(chunk_id)) {
        LOGE("Duplicate chunk ID: %s", chunk_id.c_str());
        return;
    }

    auto tokens = tokenize(text);
    if (tokens.empty()) return;

    // Compute term frequencies
    std::unordered_map<std::string, size_t> tf;
    for (const auto& token : tokens) {
        ++tf[token];
    }

    // Update inverted index
    for (const auto& [term, _] : tf) {
        inverted_index_[term].push_back(chunk_id);
    }

    chunk_term_freqs_[chunk_id] = std::move(tf);
    chunk_lengths_[chunk_id] = tokens.size();

    ++total_chunks_;
    total_length_ += tokens.size();
    avg_chunk_length_ = static_cast<double>(total_length_) / static_cast<double>(total_chunks_);
}

void BM25Index::add_chunks_batch(
    const std::vector<std::pair<std::string, std::string>>& chunks
) {
    std::lock_guard<std::mutex> lock(mutex_);

    for (const auto& [chunk_id, text] : chunks) {
        if (chunk_term_freqs_.count(chunk_id)) {
            LOGE("Duplicate chunk ID in batch: %s", chunk_id.c_str());
            continue;
        }

        auto tokens = tokenize(text);
        if (tokens.empty()) continue;

        std::unordered_map<std::string, size_t> tf;
        for (const auto& token : tokens) {
            ++tf[token];
        }

        for (const auto& [term, _] : tf) {
            inverted_index_[term].push_back(chunk_id);
        }

        chunk_term_freqs_[chunk_id] = std::move(tf);
        chunk_lengths_[chunk_id] = tokens.size();
        total_length_ += tokens.size();
        ++total_chunks_;
    }

    if (total_chunks_ > 0) {
        avg_chunk_length_ = static_cast<double>(total_length_) / static_cast<double>(total_chunks_);
    }

    LOGI("BM25 batch added, total chunks: %zu", total_chunks_);
}

void BM25Index::remove_chunk(const std::string& chunk_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto tf_it = chunk_term_freqs_.find(chunk_id);
    if (tf_it == chunk_term_freqs_.end()) return;

    // Remove from inverted index
    for (const auto& [term, _] : tf_it->second) {
        auto inv_it = inverted_index_.find(term);
        if (inv_it != inverted_index_.end()) {
            auto& ids = inv_it->second;
            ids.erase(std::remove(ids.begin(), ids.end(), chunk_id), ids.end());
            if (ids.empty()) {
                inverted_index_.erase(inv_it);
            }
        }
    }

    chunk_term_freqs_.erase(tf_it);

    auto len_it = chunk_lengths_.find(chunk_id);
    if (len_it != chunk_lengths_.end()) {
        total_length_ -= len_it->second;
        chunk_lengths_.erase(len_it);
    }
    --total_chunks_;

    avg_chunk_length_ = (total_chunks_ > 0)
        ? static_cast<double>(total_length_) / static_cast<double>(total_chunks_)
        : 0.0;
}

void BM25Index::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    inverted_index_.clear();
    chunk_term_freqs_.clear();
    chunk_lengths_.clear();
    total_chunks_ = 0;
    total_length_ = 0;
    avg_chunk_length_ = 0.0;
    LOGI("BM25 index cleared");
}

size_t BM25Index::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return total_chunks_;
}

// =============================================================================
// Search — standard BM25 scoring
// =============================================================================

std::vector<std::pair<std::string, float>> BM25Index::search(
    const std::string& query, size_t top_k
) const {
    std::lock_guard<std::mutex> lock(mutex_);

    if (total_chunks_ == 0) return {};

    auto query_tokens = tokenize(query);
    if (query_tokens.empty()) return {};

    // Collect candidate chunk IDs from inverted index
    std::unordered_set<std::string> candidate_ids;
    for (const auto& token : query_tokens) {
        auto it = inverted_index_.find(token);
        if (it != inverted_index_.end()) {
            for (const auto& id : it->second) {
                candidate_ids.insert(id);
            }
        }
    }

    if (candidate_ids.empty()) return {};

    double N = static_cast<double>(total_chunks_);

    // Score each candidate
    std::vector<std::pair<std::string, float>> scored;
    scored.reserve(candidate_ids.size());

    for (const auto& chunk_id : candidate_ids) {
        double score = 0.0;

        auto tf_it = chunk_term_freqs_.find(chunk_id);
        auto len_it = chunk_lengths_.find(chunk_id);
        if (tf_it == chunk_term_freqs_.end() || len_it == chunk_lengths_.end()) continue;

        double doc_len = static_cast<double>(len_it->second);

        for (const auto& token : query_tokens) {
            // Document frequency
            auto inv_it = inverted_index_.find(token);
            if (inv_it == inverted_index_.end()) continue;
            double df = static_cast<double>(inv_it->second.size());

            // IDF: ln((N - df + 0.5) / (df + 0.5) + 1)
            double idf = std::log((N - df + 0.5) / (df + 0.5) + 1.0);

            // Term frequency in this document
            auto term_it = tf_it->second.find(token);
            if (term_it == tf_it->second.end()) continue;
            double tf = static_cast<double>(term_it->second);

            // BM25 term score
            double numerator = tf * (static_cast<double>(k1_) + 1.0);
            double denominator = tf + static_cast<double>(k1_) *
                (1.0 - static_cast<double>(b_) +
                 static_cast<double>(b_) * doc_len / avg_chunk_length_);

            score += idf * (numerator / denominator);
        }

        if (score > 0.0) {
            scored.emplace_back(chunk_id, static_cast<float>(score));
        }
    }

    // Sort descending by score
    std::sort(scored.begin(), scored.end(),
              [](const auto& a, const auto& b) { return a.second > b.second; });

    // Return top_k
    if (scored.size() > top_k) {
        scored.resize(top_k);
    }

    return scored;
}

} // namespace rag
} // namespace runanywhere
