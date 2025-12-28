/**
 * @file rac_backend_llamacpp_register.cpp
 * @brief RunAnywhere Commons - LlamaCPP Backend Registration
 *
 * Registers the LlamaCPP backend with the module and service registries.
 * Mirrors Swift's LlamaCPPServiceProvider registration pattern.
 */

#include "rac_llm_llamacpp.h"

#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

namespace {

// Provider name
const char* const PROVIDER_NAME = "LlamaCPPService";

// Module ID
const char* const MODULE_ID = "llamacpp";

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

// Track registration state
bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_llamacpp_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module with capabilities
    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "LlamaCPP";
    module_info.version = "1.0.0";
    module_info.description = "LLM backend using llama.cpp for GGUF models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_TEXT_GENERATION};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register service provider
    rac_service_provider_t provider = {};
    provider.name = PROVIDER_NAME;
    provider.capability = RAC_CAPABILITY_TEXT_GENERATION;
    provider.priority = 100;  // Default priority
    provider.can_handle = llamacpp_can_handle;
    provider.create = llamacpp_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        // Rollback module registration on failure
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // Unregister service provider
    rac_service_unregister_provider(PROVIDER_NAME, RAC_CAPABILITY_TEXT_GENERATION);

    // Unregister module
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
