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

        float effective_threshold = threshold;
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

            if (similarity < effective_threshold) {
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

    bool serialize_to_bytes(std::vector<uint8_t>& out) const {
        std::lock_guard<std::mutex> lock(mutex_);

        // USearch binary → in-memory buffer (no filesystem access).
        const std::size_t idx_len = index_.serialized_length();
        std::vector<uint8_t> idx_buf(idx_len);
        if (idx_len > 0) {
            memory_mapped_file_t mmf(reinterpret_cast<byte_t*>(idx_buf.data()), idx_len);
            auto r = index_.save(std::move(mmf));
            if (!r) {
                LOGE("serialize: USearch save failed: %s", r.error.what());
                return false;
            }
        }

        nlohmann::json metadata;
        metadata["next_key"] = next_key_;
        metadata["chunks"] = nlohmann::json::array();
        for (const auto& [key, chunk] : chunks_) {
            nlohmann::json chunk_json;
            chunk_json["key"] = key;
            chunk_json["id"] = chunk.id;
            chunk_json["text"] = chunk.text;
            chunk_json["metadata"] = chunk.metadata;
            metadata["chunks"].push_back(chunk_json);
        }
        const std::string js = metadata.dump();

        // Frame: [u64 idx_len][idx bytes][u64 json_len][json bytes], little-endian.
        out.clear();
        out.reserve(16 + idx_len + js.size());
        auto put_u64 = [&out](uint64_t v) {
            for (int i = 0; i < 8; ++i)
                out.push_back(static_cast<uint8_t>((v >> (i * 8)) & 0xff));
        };
        put_u64(idx_len);
        out.insert(out.end(), idx_buf.begin(), idx_buf.end());
        put_u64(js.size());
        out.insert(out.end(), js.begin(), js.end());
        return true;
    }

    bool load_from_bytes(const uint8_t* data, size_t size) {
        std::lock_guard<std::mutex> lock(mutex_);

        size_t pos = 0;
        auto get_u64 = [&](uint64_t& v) -> bool {
            if (pos + 8 > size)
                return false;
            v = 0;
            for (int i = 0; i < 8; ++i)
                v |= static_cast<uint64_t>(data[pos++]) << (i * 8);
            return true;
        };

        uint64_t idx_len = 0;
        if (!get_u64(idx_len) || pos + idx_len > size) {
            LOGE("load: truncated index section");
            return false;
        }
        const uint8_t* idx_ptr = data + pos;
        pos += idx_len;

        uint64_t js_len = 0;
        if (!get_u64(js_len) || pos + js_len > size) {
            LOGE("load: truncated metadata section");
            return false;
        }
        const std::string js(reinterpret_cast<const char*>(data + pos), js_len);

        if (idx_len > 0) {
            memory_mapped_file_t mmf(const_cast<byte_t*>(reinterpret_cast<const byte_t*>(idx_ptr)),
                                     idx_len);
            auto r = index_.load(std::move(mmf));
            if (!r) {
                LOGE("load: USearch load failed: %s", r.error.what());
                return false;
            }
        }

        try {
            const auto metadata = nlohmann::json::parse(js);
            decltype(chunks_) new_chunks;
            decltype(id_to_key_) new_id_to_key;
            for (const auto& chunk_json : metadata.at("chunks")) {
                const std::size_t key = chunk_json.at("key").get<std::size_t>();
                DocumentChunk chunk;
                chunk.id = chunk_json.at("id").get<std::string>();
                chunk.text = chunk_json.at("text").get<std::string>();
                chunk.metadata = chunk_json.at("metadata");
                const std::string id = chunk.id;
                new_chunks[key] = std::move(chunk);
                new_id_to_key[id] = key;
            }
            next_key_ = metadata.at("next_key").get<std::size_t>();
            chunks_ = std::move(new_chunks);
            id_to_key_ = std::move(new_id_to_key);
        } catch (const std::exception& e) {
            LOGE("load: metadata parse failed: %s", e.what());
            index_.clear();
            chunks_.clear();
            id_to_key_.clear();
            next_key_ = 0;
            return false;
        }

        LOGI("load: restored %zu chunks (next_key=%zu)", chunks_.size(), next_key_);
        return true;
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

bool VectorStoreUSearch::serialize_to_bytes(std::vector<uint8_t>& out) const {
    return impl_->serialize_to_bytes(out);
}

bool VectorStoreUSearch::load_from_bytes(const uint8_t* data, size_t size) {
    return impl_->load_from_bytes(data, size);
}

std::vector<std::pair<std::string, std::string>> VectorStoreUSearch::all_chunk_texts() const {
    return impl_->all_chunk_texts();
}

}  // namespace runanywhere::rag
