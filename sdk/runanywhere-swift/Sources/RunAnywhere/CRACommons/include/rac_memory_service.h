/**
 * @file rac_memory_service.h
 * @brief RunAnywhere Commons - Memory/Vector Search Service Interface
 *
 * Defines the generic memory service API and vtable for multi-backend dispatch.
 * Backends (Flat, HNSW) implement the vtable and register with the service registry.
 */

#ifndef RAC_MEMORY_SERVICE_H
#define RAC_MEMORY_SERVICE_H

#include "rac_error.h"
#include "rac_memory_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * Memory Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_memory_service_ops {
    /** Add vectors with IDs and optional metadata to the index */
    rac_result_t (*add)(void* impl, const float* vectors, const uint64_t* ids,
                        const char* const* metadata, uint32_t count, uint32_t dimension);

    /** Search for k nearest neighbors */
    rac_result_t (*search)(void* impl, const float* query_vector, uint32_t dimension, uint32_t k,
                           rac_memory_search_results_t* out_results);

    /** Remove vectors by IDs */
    rac_result_t (*remove)(void* impl, const uint64_t* ids, uint32_t count);

    /** Save index to file */
    rac_result_t (*save)(void* impl, const char* path);

    /** Load index from file */
    rac_result_t (*load)(void* impl, const char* path);

    /** Get index statistics */
    rac_result_t (*get_stats)(void* impl, rac_memory_stats_t* out_stats);

    /** Destroy the service and free all resources */
    void (*destroy)(void* impl);
} rac_memory_service_ops_t;

/**
 * Memory Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_memory_service {
    /** Vtable with backend operations */
    const rac_memory_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Index identifier for reference */
    const char* index_id;
} rac_memory_service_t;

// =============================================================================
// PUBLIC API - 6 core methods (FAISS philosophy: minimal, composable)
// =============================================================================

/**
 * @brief Create a memory index
 *
 * Creates a new vector index with the given configuration.
 *
 * @param config Index configuration (dimension is required)
 * @param out_handle Output: Handle to the created index
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_create(const rac_memory_config_t* config,
                                       rac_handle_t* out_handle);

/**
 * @brief Add vectors to the index
 *
 * @param handle Index handle
 * @param vectors Flat array of float vectors (count * dimension floats)
 * @param ids Array of unique IDs for each vector (count elements)
 * @param metadata Optional array of JSON metadata strings (count elements, can be NULL)
 * @param count Number of vectors to add
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_add(rac_handle_t handle, const float* vectors,
                                    const uint64_t* ids, const char* const* metadata,
                                    uint32_t count);

/**
 * @brief Search for k nearest neighbors
 *
 * @param handle Index handle
 * @param query_vector Query vector (dimension floats)
 * @param k Number of nearest neighbors to return
 * @param out_results Output: Search results (caller must free with rac_memory_search_results_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_search(rac_handle_t handle, const float* query_vector, uint32_t k,
                                       rac_memory_search_results_t* out_results);

/**
 * @brief Remove vectors by IDs
 *
 * @param handle Index handle
 * @param ids Array of IDs to remove
 * @param count Number of IDs
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_remove(rac_handle_t handle, const uint64_t* ids, uint32_t count);

/**
 * @brief Save index to disk
 *
 * @param handle Index handle
 * @param path File path to save to (.racm extension recommended)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_save(rac_handle_t handle, const char* path);

/**
 * @brief Load index from disk
 *
 * @param path File path to load from
 * @param out_handle Output: Handle to the loaded index
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_load(const char* path, rac_handle_t* out_handle);

/**
 * @brief Get index statistics
 *
 * @param handle Index handle
 * @param out_stats Output: Index statistics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_memory_get_stats(rac_handle_t handle, rac_memory_stats_t* out_stats);

/**
 * @brief Destroy a memory index and free all resources
 *
 * @param handle Index handle to destroy
 */
RAC_API void rac_memory_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MEMORY_SERVICE_H */
