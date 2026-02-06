/**
 * @file rac_backend_memory.h
 * @brief RunAnywhere Core - Memory Backend Registration API
 *
 * Public header for registering the memory/vector search backend
 * with the commons module and service registries.
 */

#ifndef RAC_BACKEND_MEMORY_H
#define RAC_BACKEND_MEMORY_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Registers the Memory backend with the commons module and service registries.
 *
 * Should be called once during SDK initialization.
 * This registers:
 * - Module: "memory" with VECTOR_SEARCH capability
 * - Service provider: Memory vector search provider
 *
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_backend_memory_register(void);

/**
 * Unregisters the Memory backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_backend_memory_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BACKEND_MEMORY_H */
