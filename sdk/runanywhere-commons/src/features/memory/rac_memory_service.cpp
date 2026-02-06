/**
 * @file rac_memory_service.cpp
 * @brief Memory Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Memory services are created directly (not through the service registry)
 * because they require specific configuration (dimension, metric, etc.).
 */

#include "rac/features/memory/rac_memory_service.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "Memory.Service";

// Forward declaration for the unified backend create
extern "C" rac_handle_t rac_memory_backend_create_service(const rac_memory_config_t* config);

extern "C" {

// =============================================================================
// SERVICE CREATION - Direct creation (not through service registry)
// =============================================================================

rac_result_t rac_memory_create(const rac_memory_config_t* config, rac_handle_t* out_handle) {
    if (!config || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (config->dimension == 0) {
        RAC_LOG_ERROR(LOG_CAT, "Dimension must be > 0");
        return RAC_ERROR_MEMORY_INVALID_CONFIG;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating memory index: dim=%u, type=%s, metric=%d",
                 config->dimension,
                 config->index_type == RAC_INDEX_FLAT ? "flat" : "hnsw",
                 config->metric);

    rac_handle_t handle = rac_memory_backend_create_service(config);
    if (!handle) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create memory backend");
        return RAC_ERROR_INITIALIZATION_FAILED;
    }

    *out_handle = handle;
    RAC_LOG_INFO(LOG_CAT, "Memory index created successfully");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_memory_add(rac_handle_t handle, const float* vectors,
                            const uint64_t* ids, const char* const* metadata,
                            uint32_t count) {
    if (!handle || !vectors || !ids)
        return RAC_ERROR_NULL_POINTER;
    if (count == 0)
        return RAC_SUCCESS;

    auto* service = static_cast<rac_memory_service_t*>(handle);
    if (!service->ops || !service->ops->add) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // Get dimension from stats
    rac_memory_stats_t stats = {};
    if (service->ops->get_stats) {
        service->ops->get_stats(service->impl, &stats);
    }

    return service->ops->add(service->impl, vectors, ids, metadata, count, stats.dimension);
}

rac_result_t rac_memory_search(rac_handle_t handle, const float* query_vector,
                               uint32_t k, rac_memory_search_results_t* out_results) {
    if (!handle || !query_vector || !out_results)
        return RAC_ERROR_NULL_POINTER;
    if (k == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* service = static_cast<rac_memory_service_t*>(handle);
    if (!service->ops || !service->ops->search) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // Get dimension from stats
    rac_memory_stats_t stats = {};
    if (service->ops->get_stats) {
        service->ops->get_stats(service->impl, &stats);
    }

    return service->ops->search(service->impl, query_vector, stats.dimension, k, out_results);
}

rac_result_t rac_memory_remove(rac_handle_t handle, const uint64_t* ids, uint32_t count) {
    if (!handle || !ids)
        return RAC_ERROR_NULL_POINTER;
    if (count == 0)
        return RAC_SUCCESS;

    auto* service = static_cast<rac_memory_service_t*>(handle);
    if (!service->ops || !service->ops->remove) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->remove(service->impl, ids, count);
}

rac_result_t rac_memory_save(rac_handle_t handle, const char* path) {
    if (!handle || !path)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_memory_service_t*>(handle);
    if (!service->ops || !service->ops->save) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->save(service->impl, path);
}

rac_result_t rac_memory_load(const char* path, rac_handle_t* out_handle) {
    if (!path || !out_handle)
        return RAC_ERROR_NULL_POINTER;

    *out_handle = nullptr;

    // Read header to determine index type
    FILE* f = fopen(path, "rb");
    if (!f) {
        return RAC_ERROR_MEMORY_INDEX_NOT_FOUND;
    }

    char magic[4];
    uint32_t version, index_type;
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "RACM", 4) != 0) {
        fclose(f);
        return RAC_ERROR_MEMORY_CORRUPT_INDEX;
    }
    fread(&version, sizeof(uint32_t), 1, f);
    fread(&index_type, sizeof(uint32_t), 1, f);
    fclose(f);

    // Create a default config to bootstrap the index
    rac_memory_config_t config = RAC_MEMORY_CONFIG_DEFAULT;
    config.dimension = 1;  // Will be overwritten by load
    config.index_type = static_cast<rac_index_type_t>(index_type);

    rac_handle_t handle = rac_memory_backend_create_service(&config);
    if (!handle) {
        return RAC_ERROR_INITIALIZATION_FAILED;
    }

    auto* service = static_cast<rac_memory_service_t*>(handle);
    rac_result_t result = service->ops->load(service->impl, path);
    if (result != RAC_SUCCESS) {
        rac_memory_destroy(handle);
        return result;
    }

    *out_handle = handle;
    return RAC_SUCCESS;
}

rac_result_t rac_memory_get_stats(rac_handle_t handle, rac_memory_stats_t* out_stats) {
    if (!handle || !out_stats)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_memory_service_t*>(handle);
    if (!service->ops || !service->ops->get_stats) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_stats(service->impl, out_stats);
}

void rac_memory_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_memory_service_t*>(handle);

    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }

    if (service->index_id) {
        free(const_cast<char*>(service->index_id));
    }

    free(service);
}

void rac_memory_search_results_free(rac_memory_search_results_t* results) {
    if (!results)
        return;

    if (results->results) {
        for (uint32_t i = 0; i < results->count; i++) {
            if (results->results[i].metadata) {
                rac_free(results->results[i].metadata);
            }
        }
        rac_free(results->results);
        results->results = nullptr;
    }
    results->count = 0;
}

}  // extern "C"
