/**
 * @file memory_backend_flat.cpp
 * @brief Flat (brute-force) vector search backend
 *
 * Exact nearest neighbor search using linear scan with O(n*d) per query.
 * Supports L2, cosine, and inner product distance metrics.
 * Thread-safe via shared_mutex (concurrent reads, exclusive writes).
 */

#include "memory_backend_flat.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <shared_mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Memory.Flat";

// =============================================================================
// DISTANCE FUNCTIONS
// =============================================================================

namespace {

float compute_l2_distance(const float* a, const float* b, uint32_t dim) {
    float sum = 0.0f;
    for (uint32_t i = 0; i < dim; i++) {
        float diff = a[i] - b[i];
        sum += diff * diff;
    }
    return sum;
}

float compute_inner_product(const float* a, const float* b, uint32_t dim) {
    float sum = 0.0f;
    for (uint32_t i = 0; i < dim; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}

float compute_cosine_distance(const float* a, const float* b, uint32_t dim) {
    float dot = 0.0f;
    float norm_a = 0.0f;
    float norm_b = 0.0f;
    for (uint32_t i = 0; i < dim; i++) {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }
    float denom = std::sqrt(norm_a) * std::sqrt(norm_b);
    if (denom < 1e-8f) {
        return 1.0f;
    }
    return 1.0f - (dot / denom);
}

// =============================================================================
// FLAT INDEX IMPLEMENTATION
// =============================================================================

struct FlatIndex {
    uint32_t dimension;
    rac_distance_metric_t metric;

    // Vector storage: contiguous buffer for cache efficiency
    std::vector<float> vectors;
    std::vector<uint64_t> ids;
    std::unordered_map<uint64_t, std::string> metadata;
    std::unordered_map<uint64_t, size_t> id_to_index;

    mutable std::shared_mutex mutex;

    float compute_distance(const float* a, const float* b) const {
        switch (metric) {
            case RAC_DISTANCE_L2:
                return compute_l2_distance(a, b, dimension);
            case RAC_DISTANCE_COSINE:
                return compute_cosine_distance(a, b, dimension);
            case RAC_DISTANCE_INNER_PRODUCT:
                // Negate so lower = better (consistent with L2/cosine)
                return -compute_inner_product(a, b, dimension);
            default:
                return compute_l2_distance(a, b, dimension);
        }
    }
};

// =============================================================================
// VTABLE FUNCTIONS
// =============================================================================

rac_result_t flat_add(void* impl, const float* vectors, const uint64_t* ids_arr,
                      const char* const* metadata_arr, uint32_t count, uint32_t dimension) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !vectors || !ids_arr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (dimension != index->dimension) {
        return RAC_ERROR_MEMORY_DIMENSION_MISMATCH;
    }

    std::unique_lock lock(index->mutex);

    for (uint32_t i = 0; i < count; i++) {
        uint64_t id = ids_arr[i];

        // Check for duplicate - update if exists
        auto it = index->id_to_index.find(id);
        if (it != index->id_to_index.end()) {
            size_t idx = it->second;
            std::memcpy(index->vectors.data() + idx * dimension,
                        vectors + i * dimension, dimension * sizeof(float));
        } else {
            size_t idx = index->ids.size();
            index->ids.push_back(id);
            index->vectors.insert(index->vectors.end(),
                                  vectors + i * dimension,
                                  vectors + (i + 1) * dimension);
            index->id_to_index[id] = idx;
        }

        if (metadata_arr && metadata_arr[i]) {
            index->metadata[id] = metadata_arr[i];
        }
    }

    return RAC_SUCCESS;
}

rac_result_t flat_search(void* impl, const float* query_vector, uint32_t dimension, uint32_t k,
                         rac_memory_search_results_t* out_results) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !query_vector || !out_results) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (dimension != index->dimension) {
        return RAC_ERROR_MEMORY_DIMENSION_MISMATCH;
    }

    auto start = std::chrono::high_resolution_clock::now();

    std::shared_lock lock(index->mutex);

    size_t n = index->ids.size();
    uint32_t actual_k = std::min(k, static_cast<uint32_t>(n));

    if (actual_k == 0) {
        out_results->results = nullptr;
        out_results->count = 0;
        out_results->total_vectors = 0;
        out_results->search_time_us = 0;
        return RAC_SUCCESS;
    }

    // Compute all distances
    struct DistPair {
        float dist;
        size_t idx;
    };
    std::vector<DistPair> distances(n);
    for (size_t i = 0; i < n; i++) {
        distances[i].dist = index->compute_distance(
            query_vector, index->vectors.data() + i * index->dimension);
        distances[i].idx = i;
    }

    // Partial sort to get top-k
    std::partial_sort(distances.begin(), distances.begin() + actual_k, distances.end(),
                      [](const DistPair& a, const DistPair& b) { return a.dist < b.dist; });

    // Allocate results
    auto* results = static_cast<rac_memory_result_t*>(
        rac_alloc(actual_k * sizeof(rac_memory_result_t)));
    if (!results) {
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }

    for (uint32_t i = 0; i < actual_k; i++) {
        size_t idx = distances[i].idx;
        uint64_t id = index->ids[idx];

        results[i].id = id;
        results[i].score = distances[i].dist;
        results[i].metadata = nullptr;

        auto meta_it = index->metadata.find(id);
        if (meta_it != index->metadata.end()) {
            results[i].metadata = rac_strdup(meta_it->second.c_str());
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    out_results->results = results;
    out_results->count = actual_k;
    out_results->total_vectors = static_cast<uint64_t>(n);
    out_results->search_time_us = elapsed_us;

    return RAC_SUCCESS;
}

rac_result_t flat_remove(void* impl, const uint64_t* ids_arr, uint32_t count) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !ids_arr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock lock(index->mutex);

    for (uint32_t i = 0; i < count; i++) {
        auto it = index->id_to_index.find(ids_arr[i]);
        if (it == index->id_to_index.end()) {
            continue;
        }

        size_t idx = it->second;
        size_t last_idx = index->ids.size() - 1;

        if (idx != last_idx) {
            // Swap with last element
            uint64_t last_id = index->ids[last_idx];
            index->ids[idx] = last_id;
            std::memcpy(index->vectors.data() + idx * index->dimension,
                        index->vectors.data() + last_idx * index->dimension,
                        index->dimension * sizeof(float));
            index->id_to_index[last_id] = idx;
        }

        index->ids.pop_back();
        index->vectors.resize(index->ids.size() * index->dimension);
        index->id_to_index.erase(ids_arr[i]);
        index->metadata.erase(ids_arr[i]);
    }

    return RAC_SUCCESS;
}

rac_result_t flat_save(void* impl, const char* path) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !path) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::shared_lock lock(index->mutex);

    FILE* f = fopen(path, "wb");
    if (!f) {
        return RAC_ERROR_FILE_WRITE_FAILED;
    }

    // Header: "RACM" magic + version + index_type + dimension + metric + num_vectors
    const char magic[] = "RACM";
    uint32_t version = 1;
    uint32_t index_type = RAC_INDEX_FLAT;
    uint32_t dimension = index->dimension;
    uint32_t metric = static_cast<uint32_t>(index->metric);
    uint64_t num_vectors = index->ids.size();

    fwrite(magic, 1, 4, f);
    fwrite(&version, sizeof(uint32_t), 1, f);
    fwrite(&index_type, sizeof(uint32_t), 1, f);
    fwrite(&dimension, sizeof(uint32_t), 1, f);
    fwrite(&metric, sizeof(uint32_t), 1, f);
    fwrite(&num_vectors, sizeof(uint64_t), 1, f);

    // Vectors
    if (num_vectors > 0) {
        fwrite(index->vectors.data(), sizeof(float), num_vectors * dimension, f);
        fwrite(index->ids.data(), sizeof(uint64_t), num_vectors, f);
    }

    // Metadata as JSON lines
    for (size_t i = 0; i < num_vectors; i++) {
        uint64_t id = index->ids[i];
        auto meta_it = index->metadata.find(id);
        if (meta_it != index->metadata.end()) {
            // Format: id\tmeta\n
            fprintf(f, "%llu\t%s\n", static_cast<unsigned long long>(id),
                    meta_it->second.c_str());
        }
    }

    fclose(f);
    RAC_LOG_INFO(LOG_CAT, "Saved flat index: %llu vectors to %s",
                 static_cast<unsigned long long>(num_vectors), path);
    return RAC_SUCCESS;
}

rac_result_t flat_load(void* impl, const char* path) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !path) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock lock(index->mutex);

    FILE* f = fopen(path, "rb");
    if (!f) {
        return RAC_ERROR_MEMORY_INDEX_NOT_FOUND;
    }

    // Read header
    char magic[4];
    uint32_t version, index_type, dimension, metric;
    uint64_t num_vectors;

    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "RACM", 4) != 0) {
        fclose(f);
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }
    fread(&version, sizeof(uint32_t), 1, f);
    fread(&index_type, sizeof(uint32_t), 1, f);
    fread(&dimension, sizeof(uint32_t), 1, f);
    fread(&metric, sizeof(uint32_t), 1, f);
    fread(&num_vectors, sizeof(uint64_t), 1, f);

    if (index_type != RAC_INDEX_FLAT) {
        fclose(f);
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }

    // Clear and load
    index->dimension = dimension;
    index->metric = static_cast<rac_distance_metric_t>(metric);
    index->vectors.resize(num_vectors * dimension);
    index->ids.resize(num_vectors);
    index->id_to_index.clear();
    index->metadata.clear();

    if (num_vectors > 0) {
        fread(index->vectors.data(), sizeof(float), num_vectors * dimension, f);
        fread(index->ids.data(), sizeof(uint64_t), num_vectors, f);

        for (size_t i = 0; i < num_vectors; i++) {
            index->id_to_index[index->ids[i]] = i;
        }
    }

    // Read metadata lines
    char line[65536];
    while (fgets(line, sizeof(line), f)) {
        unsigned long long id;
        char* tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        id = strtoull(line, nullptr, 10);
        char* meta = tab + 1;
        // Remove trailing newline
        size_t len = strlen(meta);
        if (len > 0 && meta[len - 1] == '\n') {
            meta[len - 1] = '\0';
        }
        index->metadata[id] = meta;
    }

    fclose(f);
    RAC_LOG_INFO(LOG_CAT, "Loaded flat index: %llu vectors from %s",
                 static_cast<unsigned long long>(num_vectors), path);
    return RAC_SUCCESS;
}

rac_result_t flat_get_stats(void* impl, rac_memory_stats_t* out_stats) {
    auto* index = static_cast<FlatIndex*>(impl);
    if (!index || !out_stats) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::shared_lock lock(index->mutex);

    out_stats->num_vectors = index->ids.size();
    out_stats->dimension = index->dimension;
    out_stats->metric = index->metric;
    out_stats->index_type = RAC_INDEX_FLAT;
    out_stats->memory_usage_bytes =
        index->vectors.size() * sizeof(float) +
        index->ids.size() * sizeof(uint64_t);

    return RAC_SUCCESS;
}

void flat_destroy(void* impl) {
    auto* index = static_cast<FlatIndex*>(impl);
    delete index;
}

// Static vtable
static const rac_memory_service_ops_t g_flat_ops = {
    .add = flat_add,
    .search = flat_search,
    .remove = flat_remove,
    .save = flat_save,
    .load = flat_load,
    .get_stats = flat_get_stats,
    .destroy = flat_destroy,
};

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_result_t rac_memory_flat_create(const rac_memory_config_t* config, void** out_handle) {
    if (!config || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (config->dimension == 0) {
        return RAC_ERROR_MEMORY_INVALID_CONFIG;
    }

    auto* index = new (std::nothrow) FlatIndex();
    if (!index) {
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }

    index->dimension = config->dimension;
    index->metric = config->metric;

    if (config->max_elements > 0) {
        index->vectors.reserve(config->max_elements * config->dimension);
        index->ids.reserve(config->max_elements);
    }

    *out_handle = index;
    RAC_LOG_INFO(LOG_CAT, "Created flat index: dim=%u, metric=%d",
                 config->dimension, config->metric);
    return RAC_SUCCESS;
}

const rac_memory_service_ops_t* rac_memory_flat_get_ops(void) {
    return &g_flat_ops;
}

}  // extern "C"
