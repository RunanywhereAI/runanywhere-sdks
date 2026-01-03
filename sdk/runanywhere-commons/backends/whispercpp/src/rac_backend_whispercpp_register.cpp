/**
 * @file rac_backend_whispercpp_register.cpp
 * @brief RunAnywhere Commons - WhisperCPP Backend Registration
 *
 * Registers the WhisperCPP backend with the module and service registries.
 */

#include "rac_stt_whispercpp.h"

#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

namespace {

const char* const MODULE_ID = "whispercpp";
const char* const PROVIDER_NAME = "WhisperCPPService";

/**
 * Check if WhisperCPP can handle the request.
 * Handles .bin whisper models.
 */
rac_bool_t whispercpp_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Don't be the default STT provider (let ONNX handle that)
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_FALSE;
    }

    // Check for whisper GGML model patterns
    const char* path = request->identifier;
    size_t len = strlen(path);

    // Check for .bin extension (whisper GGML format)
    if (len >= 4) {
        const char* ext = path + len - 4;
        if (strcmp(ext, ".bin") == 0 || strcmp(ext, ".BIN") == 0) {
            // Also check if it contains "whisper" in the path
            if (strstr(path, "whisper") != nullptr || strstr(path, "ggml") != nullptr) {
                return RAC_TRUE;
            }
        }
    }

    return RAC_FALSE;
}

rac_handle_t whispercpp_create_service(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_stt_whispercpp_create(request->identifier, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_whispercpp_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module with capabilities
    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "WhisperCPP";
    module_info.version = "1.0.0";
    module_info.description = "STT backend using whisper.cpp for GGML Whisper models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register service provider with lower priority than ONNX
    // (to avoid GGML symbol conflicts when LlamaCPP is also loaded)
    rac_service_provider_t provider = {};
    provider.name = PROVIDER_NAME;
    provider.capability = RAC_CAPABILITY_STT;
    provider.priority = 50;  // Lower than ONNX (100)
    provider.can_handle = whispercpp_can_handle;
    provider.create = whispercpp_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    return RAC_SUCCESS;
}

rac_result_t rac_backend_whispercpp_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(PROVIDER_NAME, RAC_CAPABILITY_STT);
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
