/**
 * @file rac_memory_types.h
 * @brief RunAnywhere Commons - Memory/Vector Search Types and Data Structures
 *
 * Defines data structures for vector similarity search and memory/RAG
 * functionality. For the service interface, see rac_memory_service.h.
 */

#ifndef RAC_MEMORY_TYPES_H
#define RAC_MEMORY_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// DISTANCE METRICS
// =============================================================================

/**
 * @brief Distance metric for vector similarity search
 */
typedef enum rac_distance_metric {
    RAC_DISTANCE_L2 = 0,            /**< Euclidean (L2) distance */
    RAC_DISTANCE_COSINE = 1,        /**< Cosine similarity (1 - cosine) */
    RAC_DISTANCE_INNER_PRODUCT = 2, /**< Inner product (max inner product search) */
} rac_distance_metric_t;

// =============================================================================
// INDEX TYPES
// =============================================================================

/**
 * @brief Index type for vector similarity search
 */
typedef enum rac_index_type {
    RAC_INDEX_FLAT = 0, /**< Brute-force exact search (good for <10K vectors) */
    RAC_INDEX_HNSW = 1, /**< HNSW approximate nearest neighbor */
} rac_index_type_t;

// =============================================================================
// INDEX CONFIGURATION
// =============================================================================

/**
 * @brief Configuration for creating a memory index
 */
typedef struct rac_memory_config {
    /** Embedding dimension (e.g., 384, 768, 1536). Required, must be > 0. */
    uint32_t dimension;

    /** Distance metric (default: cosine) */
    rac_distance_metric_t metric;

    /** Index type (default: HNSW) */
    rac_index_type_t index_type;

    /** HNSW: max connections per node (default: 16) */
    uint32_t hnsw_m;

    /** HNSW: construction ef parameter (default: 200) */
    uint32_t hnsw_ef_construction;

    /** HNSW: search ef parameter (default: 50) */
    uint32_t hnsw_ef_search;

    /** Max elements capacity. 0 = auto-grow (default: 0) */
    uint64_t max_elements;
} rac_memory_config_t;

/**
 * @brief Default memory index configuration
 */
static const rac_memory_config_t RAC_MEMORY_CONFIG_DEFAULT = {
    .dimension = 0, /* Must be set by user */
    .metric = RAC_DISTANCE_COSINE,
    .index_type = RAC_INDEX_HNSW,
    .hnsw_m = 16,
    .hnsw_ef_construction = 200,
    .hnsw_ef_search = 50,
    .max_elements = 0};

// =============================================================================
// SEARCH RESULTS
// =============================================================================

/**
 * @brief A single search result from vector similarity search
 */
typedef struct rac_memory_result {
    /** Vector ID */
    uint64_t id;

    /** Distance/similarity score (lower is closer for L2/cosine) */
    float score;

    /** Associated metadata JSON string (owned, must free with rac_free). NULL if none. */
    char* metadata;
} rac_memory_result_t;

/**
 * @brief Collection of search results
 */
typedef struct rac_memory_search_results {
    /** Array of results sorted by score (ascending for L2/cosine) */
    rac_memory_result_t* results;

    /** Number of results returned */
    uint32_t count;

    /** Total number of vectors in the index */
    uint64_t total_vectors;

    /** Search time in microseconds */
    int64_t search_time_us;
} rac_memory_search_results_t;

// =============================================================================
// INDEX STATISTICS
// =============================================================================

/**
 * @brief Statistics about a memory index
 */
typedef struct rac_memory_stats {
    /** Number of vectors currently in the index */
    uint64_t num_vectors;

    /** Vector dimension */
    uint32_t dimension;

    /** Distance metric used */
    rac_distance_metric_t metric;

    /** Index type */
    rac_index_type_t index_type;

    /** Approximate memory usage in bytes */
    uint64_t memory_usage_bytes;
} rac_memory_stats_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free search results and all associated memory
 *
 * Frees the results array and each metadata string within it.
 *
 * @param results Results to free (can be NULL)
 */
RAC_API void rac_memory_search_results_free(rac_memory_search_results_t* results);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MEMORY_TYPES_H */
