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
    #if __has_include(<arm_fp16.h>) && !defined(__APPLE__) || (defined(__APPLE__) && !TARGET_OS_SIMULATOR)
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

#include <usearch/index_dense.hpp>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.VectorStore"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

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

        // Create metric for cosine similarity with F32 vectors
        metric_punned_t metric(
            static_cast<std::size_t>(config.dimension),
            metric_kind_t::cos_k,
            scalar_kind_t::f32_k
        );

        // Create index
        auto result = index_dense_t::make(metric, usearch_config);
        if (!result) {
            LOGE("Failed to create USearch index: %s", result.error.what());
            throw std::runtime_error("Failed to create USearch index");
        }
        index_ = std::move(result.index);

        // Reserve capacity
        index_.reserve(config.max_elements);
        LOGI("Created vector store: dim=%zu, max=%zu, connectivity=%zu",
             config.dimension, config.max_elements, config.connectivity);
    }

    bool add_chunk(const DocumentChunk& chunk) {
        std::lock_guard<std::mutex> lock(mutex_);

        if (chunk.embedding.size() != config_.dimension) {
            LOGE("Invalid embedding dimension: %zu (expected %zu)",
                 chunk.embedding.size(), config_.dimension);
            return false;
        }

        // Generate unique key from ID
        std::size_t key = std::hash<std::string>{}(chunk.id);

        // Add to USearch index
        index_.add(key, chunk.embedding.data());

        // Store metadata
        chunks_[key] = chunk;
        id_to_key_[chunk.id] = key;

        return true;
    }

    bool add_chunks_batch(const std::vector<DocumentChunk>& chunks) {
        std::lock_guard<std::mutex> lock(mutex_);

        for (const auto& chunk : chunks) {
            if (chunk.embedding.size() != config_.dimension) {
                LOGE("Invalid embedding dimension in batch");
                continue;
            }

            std::size_t key = std::hash<std::string>{}(chunk.id);
            index_.add(key, chunk.embedding.data());
            chunks_[key] = chunk;
            id_to_key_[chunk.id] = key;
        }

        return true;
    }

    std::vector<SearchResult> search(
        const std::vector<float>& query_embedding,
        size_t top_k,
        float threshold
    ) const noexcept {
        std::lock_guard<std::mutex> lock(mutex_);

        if (query_embedding.size() != config_.dimension) {
            LOGE("Invalid query embedding dimension");
            return {};
        }

        if (index_.size() == 0) {
            return {};
        }

        // Search
        auto matches = index_.search(query_embedding.data(), top_k);

        LOGI("USearch returned %zu matches from %zu total vectors", 
             matches.size(), index_.size());

        std::vector<SearchResult> results;
        results.reserve(matches.size());

        for (std::size_t i = 0; i < matches.size(); ++i) {
            auto key = matches[i].member.key;
            float distance = matches[i].distance;

            // Convert distance to similarity (cosine distance -> similarity)
            // USearch cosine distance is 1 - cosine_similarity
            float similarity = 1.0f - distance;

            LOGI("Match %zu: key=%zu, distance=%.4f, similarity=%.4f, threshold=%.4f",
                 i, key, distance, similarity, threshold);

            if (similarity < threshold) {
                LOGI("  Skipping: similarity %.4f < threshold %.4f", similarity, threshold);
                continue;
            }

            auto it = chunks_.find(key);
            if (it == chunks_.end()) {
                LOGE("Chunk key %zu not found in metadata map", key);
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

    bool remove_chunk(const std::string& chunk_id) {
        std::lock_guard<std::mutex> lock(mutex_);

        auto it = id_to_key_.find(chunk_id);
        if (it == id_to_key_.end()) {
            return false;
        }

        std::size_t key = it->second;
        index_.remove(key);
        chunks_.erase(key);
        id_to_key_.erase(it);

        return true;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        index_.clear();
        chunks_.clear();
        id_to_key_.clear();
        LOGI("Cleared vector store");
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

    bool save(const std::string& path) {
        std::lock_guard<std::mutex> lock(mutex_);
        index_.save(path.c_str());
        LOGI("Saved index to %s", path.c_str());
        return true;
    }

    bool load(const std::string& path) {
        std::lock_guard<std::mutex> lock(mutex_);
        index_.load(path.c_str());
        LOGI("Loaded index from %s", path.c_str());
        return true;
    }

private:
    VectorStoreConfig config_;
    index_dense_t index_;
    std::unordered_map<std::size_t, DocumentChunk> chunks_;
    std::unordered_map<std::string, std::size_t> id_to_key_;
    mutable std::mutex mutex_;
};

// =============================================================================
// PUBLIC API
// =============================================================================

VectorStoreUSearch::VectorStoreUSearch(const VectorStoreConfig& config)
    : impl_(std::make_unique<Impl>(config)) {
}

VectorStoreUSearch::~VectorStoreUSearch() = default;

bool VectorStoreUSearch::add_chunk(const DocumentChunk& chunk) {
    return impl_->add_chunk(chunk);
}

bool VectorStoreUSearch::add_chunks_batch(const std::vector<DocumentChunk>& chunks) {
    return impl_->add_chunks_batch(chunks);
}

std::vector<SearchResult> VectorStoreUSearch::search(
    const std::vector<float>& query_embedding,
    size_t top_k,
    float threshold
) const noexcept {
    return impl_->search(query_embedding, top_k, threshold);
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

bool VectorStoreUSearch::save(const std::string& path) const {
    return impl_->save(path);
}

bool VectorStoreUSearch::load(const std::string& path) {
    return impl_->load(path);
}

} // namespace rag
} // namespace runanywhere
