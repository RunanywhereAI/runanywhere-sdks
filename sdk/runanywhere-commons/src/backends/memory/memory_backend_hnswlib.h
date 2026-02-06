/**
 * @file memory_backend_hnswlib.h
 * @brief HNSW vector search backend using hnswlib
 *
 * Approximate nearest neighbor search using Hierarchical Navigable Small World graphs.
 * Scalable to millions of vectors with sub-millisecond search times.
 */

#ifndef RAC_MEMORY_BACKEND_HNSWLIB_H
#define RAC_MEMORY_BACKEND_HNSWLIB_H

#include "rac/features/memory/rac_memory_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Create an HNSW memory backend using hnswlib
 *
 * @param config Index configuration
 * @param out_handle Output: Backend implementation handle
 * @return RAC_SUCCESS or error code
 */
rac_result_t rac_memory_hnsw_create(const rac_memory_config_t* config, void** out_handle);

/** Get the vtable for HNSW backend operations */
const rac_memory_service_ops_t* rac_memory_hnsw_get_ops(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MEMORY_BACKEND_HNSWLIB_H */
