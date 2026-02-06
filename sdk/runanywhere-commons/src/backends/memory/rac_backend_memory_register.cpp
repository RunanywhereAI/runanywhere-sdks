/**
 * @file rac_backend_memory_register.cpp
 * @brief RunAnywhere Core - Memory Backend Registration
 *
 * Registers the memory/vector search backend with the module and service registries.
 */

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/memory/rac_memory_service.h"

static const char* LOG_CAT = "Memory";

// Forward declaration for the unified backend create
extern "C" rac_handle_t rac_memory_backend_create_service(const rac_memory_config_t* config);

namespace {

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct MemoryRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "MemoryService";
    char module_id[16] = "memory";
};

MemoryRegistryState& get_state() {
    static MemoryRegistryState state;
    return state;
}

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

rac_bool_t memory_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // We handle all VECTOR_SEARCH capability requests
    if (request->capability == RAC_CAPABILITY_VECTOR_SEARCH) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_handle_t memory_create_service(const rac_service_request_t* request, void* user_data) {
    (void)user_data;
    (void)request;

    // Memory services are created directly via rac_memory_create(),
    // not through the generic service registry. This registration
    // exists for module discovery and capability reporting.
    RAC_LOG_DEBUG(LOG_CAT, "Memory service creation should use rac_memory_create() directly");
    return nullptr;
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_memory_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "VectorSearch";
    module_info.version = "1.0.0";
    module_info.description = "Vector similarity search using hnswlib/flat backends";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_VECTOR_SEARCH};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register service provider
    rac_service_provider_t provider = {};
    provider.name = state.provider_name;
    provider.capability = RAC_CAPABILITY_VECTOR_SEARCH;
    provider.priority = 100;
    provider.can_handle = memory_can_handle;
    provider.create = memory_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(state.module_id);
        return result;
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Memory backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_memory_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(state.provider_name, RAC_CAPABILITY_VECTOR_SEARCH);
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Memory backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
