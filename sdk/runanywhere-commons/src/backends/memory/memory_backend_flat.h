/**
 * @file memory_backend_flat.h
 * @brief Flat (brute-force) vector search backend
 *
 * Exact nearest neighbor search using linear scan.
 * Ideal for small indices (<10K vectors).
 */

#ifndef RAC_MEMORY_BACKEND_FLAT_H
#define RAC_MEMORY_BACKEND_FLAT_H

#include "rac/features/memory/rac_memory_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Create a flat (brute-force) memory backend
 *
 * @param config Index configuration
 * @param out_handle Output: Backend implementation handle
 * @return RAC_SUCCESS or error code
 */
rac_result_t rac_memory_flat_create(const rac_memory_config_t* config, void** out_handle);

/** Get the vtable for flat backend operations */
const rac_memory_service_ops_t* rac_memory_flat_get_ops(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MEMORY_BACKEND_FLAT_H */
