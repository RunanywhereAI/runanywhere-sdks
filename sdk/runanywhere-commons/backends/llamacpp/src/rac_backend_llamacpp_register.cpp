/**
 * @file rac_backend_llamacpp_register.cpp
 * @brief RunAnywhere Commons - LlamaCPP Backend Registration
 *
 * Registers the LlamaCPP backend with the module and service registries.
 * Mirrors Swift's LlamaCPPServiceProvider registration pattern.
 *
 * Uses function-local statics to avoid static initialization order issues
 * when called from Swift.
 */

#include "rac_llm_llamacpp.h"

#include <cstring>
#include <mutex>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// Category for logging
static const char* LOG_CAT = "LlamaCPP";

// =============================================================================
// REGISTRY STATE - Function-local statics to avoid initialization order issues
// =============================================================================

namespace {

/**
 * Registry state using function-local static to ensure proper initialization.
 * This avoids the "static initialization order fiasco" when Swift calls
 * rac_backend_llamacpp_register() before C++ global statics are initialized.
 */
struct LlamaCPPRegistryState {
    std::mutex mutex;
    bool registered = false;
    // Use char arrays to avoid any dynamic allocation during initialization
    char provider_name[32] = "LlamaCPPService";
    char module_id[16] = "llamacpp";
};

/**
 * Get the registry state singleton using Meyers' singleton pattern.
 * Function-local static guarantees thread-safe initialization on first use.
 * NOTE: No logging here - this is called during static initialization
 */
LlamaCPPRegistryState& get_state() {
    static LlamaCPPRegistryState state;
    return state;
}

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

/**
 * Check if this provider can handle the request.
 *
 * Mirrors Swift's canHandle closure in LlamaCPPServiceProvider:
 * canHandle: { modelId in modelId?.hasSuffix(".gguf") ?? true }
 */
rac_bool_t llamacpp_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // If no identifier specified, we can handle it (default provider)
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;
    }

    // Check if model path ends with .gguf
    const char* path = request->identifier;
    size_t len = strlen(path);
    if (len >= 5) {
        const char* ext = path + len - 5;
        if (strcmp(ext, ".gguf") == 0 || strcmp(ext, ".GGUF") == 0) {
            return RAC_TRUE;
        }
    }

    return RAC_FALSE;
}

/**
 * Create a LlamaCPP LLM service.
 *
 * Mirrors Swift's factory closure in LlamaCPPServiceProvider.
 */
rac_handle_t llamacpp_create_service(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_llm_llamacpp_create(request->identifier,
                                                  nullptr,  // Use default config
                                                  &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_llamacpp_register(void) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_backend_llamacpp_register() - ENTRY");

    // Get state using function-local static (safe initialization)
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        RAC_LOG_DEBUG(LOG_CAT, "Already registered, returning");
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module with capabilities
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "LlamaCPP";
    module_info.version = "1.0.0";
    module_info.description = "LLM backend using llama.cpp for GGUF models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_TEXT_GENERATION};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    RAC_LOG_DEBUG(LOG_CAT, "Registering module...");
    rac_result_t result = rac_module_register(&module_info);

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        RAC_LOG_ERROR(LOG_CAT, "Module registration failed: %d", result);
        return result;
    }

    // Register service provider
    rac_service_provider_t provider = {};
    provider.name = state.provider_name;
    provider.capability = RAC_CAPABILITY_TEXT_GENERATION;
    provider.priority = 100;  // Default priority
    provider.can_handle = llamacpp_can_handle;
    provider.create = llamacpp_create_service;
    provider.user_data = nullptr;

    RAC_LOG_DEBUG(LOG_CAT, "Registering service provider...");
    result = rac_service_register_provider(&provider);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Service provider registration failed: %d, rolling back", result);
        rac_module_unregister(state.module_id);
        return result;
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_backend_llamacpp_unregister() - ENTRY");

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        RAC_LOG_WARNING(LOG_CAT, "Not registered, returning error");
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // Unregister service provider
    rac_service_unregister_provider(state.provider_name, RAC_CAPABILITY_TEXT_GENERATION);

    // Unregister module
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Backend unregistered successfully");
    return RAC_SUCCESS;
}

}  // extern "C"
