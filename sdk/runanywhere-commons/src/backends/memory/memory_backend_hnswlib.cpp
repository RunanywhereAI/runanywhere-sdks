/**
 * @file memory_backend_hnswlib.cpp
 * @brief HNSW vector search backend using hnswlib
 *
 * Approximate nearest neighbor search via Hierarchical Navigable Small World graphs.
 * Thread-safe: hnswlib supports concurrent reads; writes are serialized via mutex.
 * Metadata is stored in a parallel map since hnswlib only stores vectors.
 */

#include "memory_backend_hnswlib.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <hnswlib/hnswlib.h>

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Memory.HNSW";

static const size_t DEFAULT_MAX_ELEMENTS = 10000;
static const size_t RESIZE_FACTOR = 2;

namespace {

// =============================================================================
// HNSW INDEX IMPLEMENTATION
// =============================================================================

struct HNSWIndex {
    uint32_t dimension;
    rac_distance_metric_t metric;
    uint32_t hnsw_ef_search;

    std::unique_ptr<hnswlib::SpaceInterface<float>> space;
    std::unique_ptr<hnswlib::HierarchicalNSW<float>> hnsw;

    // Metadata stored separately (hnswlib only stores vectors)
    std::unordered_map<uint64_t, std::string> metadata;

    mutable std::shared_mutex mutex;
    size_t max_elements;

    void ensure_capacity(size_t needed) {
        if (hnsw->cur_element_count + needed > max_elements) {
            size_t new_max = std::max(max_elements * RESIZE_FACTOR,
                                      hnsw->cur_element_count + needed);
            hnsw->resizeIndex(new_max);
            max_elements = new_max;
            RAC_LOG_DEBUG(LOG_CAT, "Resized HNSW index to %zu", new_max);
        }
    }
};

// =============================================================================
// VTABLE FUNCTIONS
// =============================================================================

rac_result_t hnsw_add(void* impl, const float* vectors, const uint64_t* ids,
                      const char* const* metadata_arr, uint32_t count, uint32_t dimension) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !vectors || !ids) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (dimension != index->dimension) {
        return RAC_ERROR_MEMORY_DIMENSION_MISMATCH;
    }

    std::unique_lock lock(index->mutex);

    index->ensure_capacity(count);

    for (uint32_t i = 0; i < count; i++) {
        const float* vec = vectors + i * dimension;
        hnswlib::labeltype label = static_cast<hnswlib::labeltype>(ids[i]);

        try {
            index->hnsw->addPoint(vec, label, /* replace_deleted= */ true);
        } catch (const std::exception& e) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to add vector id=%llu: %s",
                          static_cast<unsigned long long>(ids[i]), e.what());
            return RAC_ERROR_MEMORY_INDEX_FULL;
        }

        if (metadata_arr && metadata_arr[i]) {
            index->metadata[ids[i]] = metadata_arr[i];
        }
    }

    return RAC_SUCCESS;
}

rac_result_t hnsw_search(void* impl, const float* query_vector, uint32_t dimension, uint32_t k,
                         rac_memory_search_results_t* out_results) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !query_vector || !out_results) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (dimension != index->dimension) {
        return RAC_ERROR_MEMORY_DIMENSION_MISMATCH;
    }

    auto start = std::chrono::high_resolution_clock::now();

    std::shared_lock lock(index->mutex);

    size_t n = index->hnsw->cur_element_count;
    uint32_t actual_k = std::min(k, static_cast<uint32_t>(n));

    if (actual_k == 0) {
        out_results->results = nullptr;
        out_results->count = 0;
        out_results->total_vectors = 0;
        out_results->search_time_us = 0;
        return RAC_SUCCESS;
    }

    // Set search ef
    index->hnsw->setEf(index->hnsw_ef_search);

    std::priority_queue<std::pair<float, hnswlib::labeltype>> result;
    try {
        result = index->hnsw->searchKnn(query_vector, actual_k);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Search failed: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }

    // Convert priority queue to array (results come in max-distance-first order)
    uint32_t result_count = static_cast<uint32_t>(result.size());
    auto* results = static_cast<rac_memory_result_t*>(
        rac_alloc(result_count * sizeof(rac_memory_result_t)));
    if (!results) {
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }

    // Fill in reverse order (priority queue gives max-first, we want min-first)
    for (int32_t i = static_cast<int32_t>(result_count) - 1; i >= 0; i--) {
        auto& top = result.top();
        uint64_t id = static_cast<uint64_t>(top.second);

        results[i].id = id;
        results[i].score = top.first;
        results[i].metadata = nullptr;

        auto meta_it = index->metadata.find(id);
        if (meta_it != index->metadata.end()) {
            results[i].metadata = rac_strdup(meta_it->second.c_str());
        }

        result.pop();
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    out_results->results = results;
    out_results->count = result_count;
    out_results->total_vectors = static_cast<uint64_t>(n);
    out_results->search_time_us = elapsed_us;

    return RAC_SUCCESS;
}

rac_result_t hnsw_remove(void* impl, const uint64_t* ids, uint32_t count) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !ids) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock lock(index->mutex);

    for (uint32_t i = 0; i < count; i++) {
        hnswlib::labeltype label = static_cast<hnswlib::labeltype>(ids[i]);
        try {
            index->hnsw->markDelete(label);
        } catch (...) {
            // Element not found, skip silently
        }
        index->metadata.erase(ids[i]);
    }

    return RAC_SUCCESS;
}

rac_result_t hnsw_save(void* impl, const char* path) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !path) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::shared_lock lock(index->mutex);

    // Save HNSW index using hnswlib's native serialization
    std::string hnsw_path = std::string(path) + ".hnsw";
    std::string meta_path = std::string(path) + ".meta";

    try {
        index->hnsw->saveIndex(hnsw_path);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to save HNSW index: %s", e.what());
        return RAC_ERROR_FILE_WRITE_FAILED;
    }

    // Save header and metadata
    FILE* f = fopen(path, "wb");
    if (!f) {
        return RAC_ERROR_FILE_WRITE_FAILED;
    }

    const char magic[] = "RACM";
    uint32_t version = 1;
    uint32_t index_type = RAC_INDEX_HNSW;
    uint32_t dimension = index->dimension;
    uint32_t metric = static_cast<uint32_t>(index->metric);
    uint64_t num_vectors = index->hnsw->cur_element_count;
    uint32_t ef_search = index->hnsw_ef_search;

    fwrite(magic, 1, 4, f);
    fwrite(&version, sizeof(uint32_t), 1, f);
    fwrite(&index_type, sizeof(uint32_t), 1, f);
    fwrite(&dimension, sizeof(uint32_t), 1, f);
    fwrite(&metric, sizeof(uint32_t), 1, f);
    fwrite(&num_vectors, sizeof(uint64_t), 1, f);
    fwrite(&ef_search, sizeof(uint32_t), 1, f);

    // Metadata as lines
    for (auto& [id, meta] : index->metadata) {
        fprintf(f, "%llu\t%s\n", static_cast<unsigned long long>(id), meta.c_str());
    }

    fclose(f);

    RAC_LOG_INFO(LOG_CAT, "Saved HNSW index: %llu vectors to %s",
                 static_cast<unsigned long long>(num_vectors), path);
    return RAC_SUCCESS;
}

rac_result_t hnsw_load(void* impl, const char* path) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !path) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock lock(index->mutex);

    // Read header
    FILE* f = fopen(path, "rb");
    if (!f) {
        return RAC_ERROR_MEMORY_INDEX_NOT_FOUND;
    }

    char magic[4];
    uint32_t version, index_type, dimension, metric;
    uint64_t num_vectors;
    uint32_t ef_search;

    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "RACM", 4) != 0) {
        fclose(f);
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }
    fread(&version, sizeof(uint32_t), 1, f);
    fread(&index_type, sizeof(uint32_t), 1, f);
    fread(&dimension, sizeof(uint32_t), 1, f);
    fread(&metric, sizeof(uint32_t), 1, f);
    fread(&num_vectors, sizeof(uint64_t), 1, f);
    fread(&ef_search, sizeof(uint32_t), 1, f);

    if (index_type != RAC_INDEX_HNSW) {
        fclose(f);
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }

    // Read metadata
    index->metadata.clear();
    char line[65536];
    while (fgets(line, sizeof(line), f)) {
        unsigned long long id;
        char* tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        id = strtoull(line, nullptr, 10);
        char* meta = tab + 1;
        size_t len = strlen(meta);
        if (len > 0 && meta[len - 1] == '\n') {
            meta[len - 1] = '\0';
        }
        index->metadata[id] = meta;
    }
    fclose(f);

    // Load HNSW index
    std::string hnsw_path = std::string(path) + ".hnsw";
    index->dimension = dimension;
    index->metric = static_cast<rac_distance_metric_t>(metric);
    index->hnsw_ef_search = ef_search;

    // Recreate space
    switch (index->metric) {
        case RAC_DISTANCE_COSINE:
        case RAC_DISTANCE_L2:
            index->space = std::make_unique<hnswlib::L2Space>(dimension);
            break;
        case RAC_DISTANCE_INNER_PRODUCT:
            index->space = std::make_unique<hnswlib::InnerProductSpace>(dimension);
            break;
    }

    try {
        index->hnsw = std::make_unique<hnswlib::HierarchicalNSW<float>>(
            index->space.get(), hnsw_path, false, num_vectors, true);
        index->max_elements = index->hnsw->max_elements_;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load HNSW index: %s", e.what());
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }

    RAC_LOG_INFO(LOG_CAT, "Loaded HNSW index: %llu vectors from %s",
                 static_cast<unsigned long long>(num_vectors), path);
    return RAC_SUCCESS;
}

rac_result_t hnsw_get_stats(void* impl, rac_memory_stats_t* out_stats) {
    auto* index = static_cast<HNSWIndex*>(impl);
    if (!index || !out_stats) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::shared_lock lock(index->mutex);

    out_stats->num_vectors = index->hnsw->cur_element_count;
    out_stats->dimension = index->dimension;
    out_stats->metric = index->metric;
    out_stats->index_type = RAC_INDEX_HNSW;
    // Approximate memory: vector data + graph connections
    size_t vec_bytes = index->hnsw->cur_element_count * index->dimension * sizeof(float);
    size_t graph_bytes = index->hnsw->cur_element_count * index->hnsw->size_links_per_element_;
    out_stats->memory_usage_bytes = vec_bytes + graph_bytes;

    return RAC_SUCCESS;
}

void hnsw_destroy(void* impl) {
    auto* index = static_cast<HNSWIndex*>(impl);
    delete index;
}

// Static vtable
static const rac_memory_service_ops_t g_hnsw_ops = {
    .add = hnsw_add,
    .search = hnsw_search,
    .remove = hnsw_remove,
    .save = hnsw_save,
    .load = hnsw_load,
    .get_stats = hnsw_get_stats,
    .destroy = hnsw_destroy,
};

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_result_t rac_memory_hnsw_create(const rac_memory_config_t* config, void** out_handle) {
    if (!config || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (config->dimension == 0) {
        return RAC_ERROR_MEMORY_INVALID_CONFIG;
    }

    auto* index = new (std::nothrow) HNSWIndex();
    if (!index) {
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }

    index->dimension = config->dimension;
    index->metric = config->metric;
    index->hnsw_ef_search = config->hnsw_ef_search > 0 ? config->hnsw_ef_search : 50;

    // Create hnswlib space
    switch (config->metric) {
        case RAC_DISTANCE_COSINE:
        case RAC_DISTANCE_L2:
            index->space = std::make_unique<hnswlib::L2Space>(config->dimension);
            break;
        case RAC_DISTANCE_INNER_PRODUCT:
            index->space = std::make_unique<hnswlib::InnerProductSpace>(config->dimension);
            break;
        default:
            delete index;
            return RAC_ERROR_MEMORY_INVALID_CONFIG;
    }

    // Create HNSW index
    size_t max_elements = config->max_elements > 0 ? config->max_elements : DEFAULT_MAX_ELEMENTS;
    uint32_t M = config->hnsw_m > 0 ? config->hnsw_m : 16;
    uint32_t ef_construction = config->hnsw_ef_construction > 0 ? config->hnsw_ef_construction : 200;

    try {
        index->hnsw = std::make_unique<hnswlib::HierarchicalNSW<float>>(
            index->space.get(), max_elements, M, ef_construction,
            /* random_seed= */ 42, /* allow_replace_deleted= */ true);
        index->max_elements = max_elements;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create HNSW index: %s", e.what());
        delete index;
        return RAC_ERROR_INITIALIZATION_FAILED;
    }

    *out_handle = index;
    RAC_LOG_INFO(LOG_CAT, "Created HNSW index: dim=%u, M=%u, ef_c=%u, metric=%d",
                 config->dimension, M, ef_construction, config->metric);
    return RAC_SUCCESS;
}

const rac_memory_service_ops_t* rac_memory_hnsw_get_ops(void) {
    return &g_hnsw_ops;
}

}  // extern "C"
