/**
 * @file vector_store_usearch.cpp
 * @brief Vector Store Implementation using USearch
 */

// Disable FP16 and SIMD before including USearch headers
#define USEARCH_USE_FP16LIB 0
#define USEARCH_USE_SIMSIMD 0

// Define f16_native_t based on platform capabilities
// USearch expects this type to be defined when FP16LIB and SIMSIMD are disabled
#if defined(__ARM_ARCH) || defined(__aarch64__) || defined(_M_ARM64)
// Try to use native ARM FP16 if available (device builds)
#if __has_include(<arm_fp16.h>) && (!defined(__APPLE__) || (defined(__APPLE__) && !TARGET_OS_SIMULATOR))
#include <arm_fp16.h>
using f16_native_t = __fp16;
#else
// Fallback for ARM without native FP16 (e.g., iOS Simulator on Apple Silicon)
#include <cstdint>
using f16_native_t = uint16_t;  // Use binary16 representation
#endif
#else
// Non-ARM platforms (x86, x86_64)
#include <cstdint>
using f16_native_t = uint16_t;  // Use binary16 representation
#endif

#include "vector_store_usearch.h"

#include <fstream>
#include <optional>
#include <usearch/index_dense.hpp>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.VectorStore"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGW(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere::rag {

using namespace unum::usearch;

// =============================================================================
// IMPLEMENTATION
// =============================================================================

class VectorStoreUSearch::Impl {
   public:
    explicit Impl(const VectorStoreConfig& config) : config_(config) {
        // Configure USearch index
        index_dense_config_t usearch_config;
        usearch_config.connectivity = config.connectivity;
        usearch_config.expansion_add = config.expansion_add;
        usearch_config.expansion_search = config.expansion_search;

        // Create metric for cosine similarity. Quantize further for RAM, switch to f32 for
        // precision
        metric_punned_t metric(static_cast<std::size_t>(config.dimension), metric_kind_t::cos_k,
                               scalar_kind_t::f16_k);

        // Create index
        auto result = index_dense_t::make(metric, usearch_config);
        if (!result) {
            RAC_LOG_ERROR(LOG_TAG, "Failed to create USearch index: %s", result.error.what());
            throw std::runtime_error("Failed to create USearch index");
        }
        index_ = std::move(result.index);

        // Reserve capacity
        index_.reserve(config.max_elements);
        LOGI("Created vector store: dim=%zu, max=%zu, connectivity=%zu, quantization=f16",
             config.dimension, config.max_elements, config.connectivity);
    }

    bool add_chunk(const DocumentChunk& chunk) {
        std::lock_guard<std::mutex> lock(mutex_);

        if (chunk.embedding.size() != config_.dimension) {
            RAC_LOG_ERROR(LOG_TAG, "Invalid embedding dimension: %zu (expected %zu)",
                          chunk.embedding.size(), config_.dimension);
            return false;
        }

        // Check for duplicate ID
        if (id_to_key_.find(chunk.id) != id_to_key_.end()) {
            RAC_LOG_ERROR(LOG_TAG, "Duplicate chunk ID: %s", chunk.id.c_str());
            return false;
        }

        // Generate unique key using monotonically increasing counter (no collisions)
        std::size_t key = next_key_++;

        // Add to USearch index
        auto add_result = index_.add(key, chunk.embedding.data());
        if (!add_result) {
            RAC_LOG_ERROR(LOG_TAG, "Failed to add chunk to index: %s", add_result.error.what());
            return false;
        }

        // Store metadata
        DocumentChunk metadata_copy = chunk;
        metadata_copy.embedding.clear();
        metadata_copy.embedding.shrink_to_fit();
        chunks_[key] = std::move(metadata_copy);
        id_to_key_[chunk.id] = key;

        return true;
    }

    bool add_chunks_batch(const std::vector<DocumentChunk>& chunks) {
        std::lock_guard<std::mutex> lock(mutex_);
        bool any_added = false;

        for (const auto& chunk : chunks) {
            if (chunk.embedding.size() != config_.dimension) {
                RAC_LOG_ERROR(LOG_TAG, "Invalid embedding dimension in batch");
                continue;
            }

            // Check for duplicate ID
            if (id_to_key_.find(chunk.id) != id_to_key_.end()) {
                RAC_LOG_ERROR(LOG_TAG, "Duplicate chunk ID in batch: %s", chunk.id.c_str());
                continue;
            }

            // Generate unique key using monotonically increasing counter (no collisions)
            std::size_t key = next_key_++;
            auto add_result = index_.add(key, chunk.embedding.data());
            if (!add_result) {
                RAC_LOG_ERROR(LOG_TAG, "Failed to add chunk to batch: %s", add_result.error.what());
                continue;
            }
            // Store metadata
            DocumentChunk metadata_copy = chunk;
            metadata_copy.embedding.clear();
            metadata_copy.embedding.shrink_to_fit();
            chunks_[key] = std::move(metadata_copy);
            id_to_key_[chunk.id] = key;
            any_added = true;
        }

        return any_added;
    }

    std::vector<SearchResult> search(const std::vector<float>& query_embedding, size_t top_k,
                                     float threshold) const {
        std::lock_guard<std::mutex> lock(mutex_);

        if (query_embedding.size() != config_.dimension) {
            RAC_LOG_ERROR(LOG_TAG, "Invalid query embedding dimension");
            return {};
        }

        if (index_.size() == 0) {
            return {};
        }

        // Search for the closest K matches
        auto matches = index_.search(query_embedding.data(), top_k);

        RAC_LOG_INFO(LOG_TAG, "USearch returned %zu matches from %zu total vectors", matches.size(),
                     index_.size());

        // Real-RAG retrieval: let top_k (+ downstream fusion/rerank) do the
        // selecting rather than an absolute cosine floor. all-MiniLM-class
        // scores are low and often near-zero/negative even for relevant chunks,
        // so any positive floor silently drops real matches (a multi-chunk doc
        // then retrieves nothing). Only apply a floor when the caller explicitly
        // set a positive threshold; <= 0 means accept-all, ranked by score.
        const bool apply_floor = threshold > 0.0f;
        if (threshold > 0.5f) {
            LOGW(
                "Similarity threshold %.2f is high — dense embeddings (e.g. all-MiniLM) rarely "
                "exceed 0.3-0.5",
                threshold);
        }

        std::vector<SearchResult> results;
        results.reserve(matches.size());

        for (std::size_t i = 0; i < matches.size(); ++i) {
            auto key = matches[i].member.key;
            float distance = matches[i].distance;

            // Convert distance to similarity (cosine distance -> similarity)
            // USearch cosine distance is 1 - cosine_similarity
            float similarity = 1.0f - distance;

            if (apply_floor && similarity < threshold) {
                continue;
            }

            auto it = chunks_.find(key);
            if (it == chunks_.end()) {
                RAC_LOG_ERROR(LOG_TAG, "Chunk key %zu not found in metadata map", key);
                continue;
            }

            SearchResult result;
            result.chunk_id = it->second.id;
            result.id = it->second.id;  // Alias
            result.text = it->second.text;
            result.similarity = similarity;
            result.score = similarity;  // Alias
            result.metadata = it->second.metadata;
            results.push_back(std::move(result));
        }

        return results;
    }

    std::optional<DocumentChunk> get_chunk(const std::string& chunk_id) const {
        std::lock_guard<std::mutex> lock(mutex_);

        auto it = id_to_key_.find(chunk_id);
        if (it == id_to_key_.end()) {
            return std::nullopt;
        }

        auto chunk_it = chunks_.find(it->second);
        if (chunk_it == chunks_.end()) {
            return std::nullopt;
        }

        return chunk_it->second;
    }

    bool remove_chunk(const std::string& chunk_id) {
        std::lock_guard<std::mutex> lock(mutex_);

        auto it = id_to_key_.find(chunk_id);
        if (it == id_to_key_.end()) {
            return false;
        }

        std::size_t key = it->second;
        auto remove_result = index_.remove(key);
        if (!remove_result) {
            RAC_LOG_ERROR(LOG_TAG, "Failed to remove chunk from index: %s",
                          remove_result.error.what());
            return false;
        }
        chunks_.erase(key);
        id_to_key_.erase(it);

        return true;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        index_.clear();
        // USearch clear() releases the internal capacity buffers (vectors_lookup_),
        // so a subsequent add() would write past an unreserved slot and crash.
        // Re-reserve the configured headroom to leave the store usable, matching
        // the constructor.
        index_.reserve(config_.max_elements);
        chunks_.clear();
        id_to_key_.clear();
        next_key_ = 0;  // Reset counter
        RAC_LOG_INFO(LOG_TAG, "Cleared vector store");
    }

    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return index_.size();
    }

    size_t memory_usage() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return index_.memory_usage();
    }

    nlohmann::json get_statistics() const {
        std::lock_guard<std::mutex> lock(mutex_);

        nlohmann::json stats;
        stats["num_chunks"] = index_.size();
        stats["dimension"] = config_.dimension;
        stats["memory_bytes"] = index_.memory_usage();
        stats["connectivity"] = config_.connectivity;
        stats["max_elements"] = config_.max_elements;

        return stats;
    }

    std::vector<std::pair<std::string, std::string>> all_chunk_texts() const {
        std::lock_guard<std::mutex> lock(mutex_);
        std::vector<std::pair<std::string, std::string>> out;
        out.reserve(chunks_.size());
        for (const auto& [key, chunk] : chunks_) {
            (void)key;
            out.emplace_back(chunk.id, chunk.text);
        }
        return out;
    }

   private:
    VectorStoreConfig config_;
    index_dense_t index_;
    std::unordered_map<std::size_t, DocumentChunk> chunks_;
    std::unordered_map<std::string, std::size_t> id_to_key_;
    std::size_t next_key_ = 0;  // Monotonically increasing counter for collision-free keys
    mutable std::mutex mutex_;
};

// =============================================================================
// PUBLIC API
// =============================================================================

VectorStoreUSearch::VectorStoreUSearch(const VectorStoreConfig& config)
    : impl_(std::make_unique<Impl>(config)) {}

VectorStoreUSearch::~VectorStoreUSearch() = default;

bool VectorStoreUSearch::add_chunk(const DocumentChunk& chunk) {
    return impl_->add_chunk(chunk);
}

bool VectorStoreUSearch::add_chunks_batch(const std::vector<DocumentChunk>& chunks) {
    return impl_->add_chunks_batch(chunks);
}

std::vector<SearchResult> VectorStoreUSearch::search(const std::vector<float>& query_embedding,
                                                     size_t top_k, float threshold) const noexcept {
    try {
        return impl_->search(query_embedding, top_k, threshold);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "search() exception: %s", e.what());
        return {};
    } catch (...) {
        RAC_LOG_ERROR(LOG_TAG, "search() unknown exception");
        return {};
    }
}

std::optional<DocumentChunk> VectorStoreUSearch::get_chunk(const std::string& chunk_id) const {
    return impl_->get_chunk(chunk_id);
}

bool VectorStoreUSearch::remove_chunk(const std::string& chunk_id) {
    return impl_->remove_chunk(chunk_id);
}

void VectorStoreUSearch::clear() {
    impl_->clear();
}

size_t VectorStoreUSearch::size() const {
    return impl_->size();
}

size_t VectorStoreUSearch::memory_usage() const {
    return impl_->memory_usage();
}

nlohmann::json VectorStoreUSearch::get_statistics() const {
    return impl_->get_statistics();
}

std::vector<std::pair<std::string, std::string>> VectorStoreUSearch::all_chunk_texts() const {
    return impl_->all_chunk_texts();
}

}  // namespace runanywhere::rag
