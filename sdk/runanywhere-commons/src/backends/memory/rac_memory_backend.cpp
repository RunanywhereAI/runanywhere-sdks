/**
 * @file rac_memory_backend.cpp
 * @brief Memory backend - Unified dispatch for flat and HNSW backends
 *
 * Routes memory index creation to the appropriate backend based on config.
 * Provides the combined create function used by the service layer.
 */

#include "memory_backend_flat.h"
#include "memory_backend_hnswlib.h"

#include <cstdlib>

#include "rac/core/rac_logger.h"
#include "rac/features/memory/rac_memory_service.h"

static const char* LOG_CAT = "Memory.Backend";

extern "C" {

/**
 * Create a memory service with the appropriate backend.
 * Allocates an rac_memory_service_t and routes to flat or HNSW.
 */
rac_handle_t rac_memory_backend_create_service(const rac_memory_config_t* config) {
    if (!config) {
        return nullptr;
    }

    void* backend_handle = nullptr;
    const rac_memory_service_ops_t* ops = nullptr;
    rac_result_t result;

    switch (config->index_type) {
        case RAC_INDEX_FLAT:
            result = rac_memory_flat_create(config, &backend_handle);
            ops = rac_memory_flat_get_ops();
            break;
        case RAC_INDEX_HNSW:
            result = rac_memory_hnsw_create(config, &backend_handle);
            ops = rac_memory_hnsw_get_ops();
            break;
        default:
            RAC_LOG_ERROR(LOG_CAT, "Unknown index type: %d", config->index_type);
            return nullptr;
    }

    if (result != RAC_SUCCESS || !backend_handle) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create backend: %d", result);
        return nullptr;
    }

    // Allocate service struct
    auto* service = static_cast<rac_memory_service_t*>(malloc(sizeof(rac_memory_service_t)));
    if (!service) {
        ops->destroy(backend_handle);
        return nullptr;
    }

    service->ops = ops;
    service->impl = backend_handle;
    service->index_id = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Memory service created: type=%s",
                 config->index_type == RAC_INDEX_FLAT ? "flat" : "hnsw");
    return service;
}

}  // extern "C"
