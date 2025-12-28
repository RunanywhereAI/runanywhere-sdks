/**
 * @file rac_backend_onnx_register.cpp
 * @brief RunAnywhere Commons - ONNX Backend Registration
 *
 * Registers the ONNX backend with the module and service registries.
 * Mirrors Swift's ONNXServiceProvider registration pattern.
 */

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATIONS
// =============================================================================

namespace {

// Module info
const char* const MODULE_ID = "onnx";

// Provider names
const char* const STT_PROVIDER_NAME = "ONNXSTTService";
const char* const TTS_PROVIDER_NAME = "ONNXTTSService";
const char* const VAD_PROVIDER_NAME = "ONNXVADService";

// =============================================================================
// STT PROVIDER
// =============================================================================

/**
 * Check if ONNX can handle STT request.
 * Mirrors Swift's canHandle: { modelId in modelId?.contains("whisper") ?? true }
 */
rac_bool_t onnx_stt_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Default provider if no specific model
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;
    }

    // Check for ONNX model patterns
    const char* path = request->identifier;
    if (strstr(path, "whisper") != nullptr || strstr(path, "zipformer") != nullptr ||
        strstr(path, "paraformer") != nullptr || strstr(path, ".onnx") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_handle_t onnx_stt_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_stt_onnx_create(request->identifier, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

// =============================================================================
// TTS PROVIDER
// =============================================================================

rac_bool_t onnx_tts_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Default TTS provider
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;
    }

    // Check for TTS model patterns
    const char* path = request->identifier;
    if (strstr(path, "piper") != nullptr || strstr(path, "vits") != nullptr ||
        strstr(path, ".onnx") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_handle_t onnx_tts_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_tts_onnx_create(request->identifier, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

// =============================================================================
// VAD PROVIDER
// =============================================================================

rac_bool_t onnx_vad_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;
    (void)request;

    // VAD always handled by ONNX (Silero VAD)
    return RAC_TRUE;
}

rac_handle_t onnx_vad_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    const char* model_path = nullptr;
    if (request != nullptr) {
        model_path = request->identifier;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_vad_onnx_create(model_path, nullptr, &handle);

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

rac_result_t rac_backend_onnx_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module with capabilities
    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "ONNX Runtime";
    module_info.version = "1.0.0";
    module_info.description = "STT/TTS/VAD backend using ONNX Runtime";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT, RAC_CAPABILITY_TTS, RAC_CAPABILITY_VAD};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 3;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register STT provider
    rac_service_provider_t stt_provider = {};
    stt_provider.name = STT_PROVIDER_NAME;
    stt_provider.capability = RAC_CAPABILITY_STT;
    stt_provider.priority = 100;
    stt_provider.can_handle = onnx_stt_can_handle;
    stt_provider.create = onnx_stt_create;
    stt_provider.user_data = nullptr;

    result = rac_service_register_provider(&stt_provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(MODULE_ID);
        return result;
    }

    // Register TTS provider
    rac_service_provider_t tts_provider = {};
    tts_provider.name = TTS_PROVIDER_NAME;
    tts_provider.capability = RAC_CAPABILITY_TTS;
    tts_provider.priority = 100;
    tts_provider.can_handle = onnx_tts_can_handle;
    tts_provider.create = onnx_tts_create;
    tts_provider.user_data = nullptr;

    result = rac_service_register_provider(&tts_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
        rac_module_unregister(MODULE_ID);
        return result;
    }

    // Register VAD provider
    rac_service_provider_t vad_provider = {};
    vad_provider.name = VAD_PROVIDER_NAME;
    vad_provider.capability = RAC_CAPABILITY_VAD;
    vad_provider.priority = 100;
    vad_provider.can_handle = onnx_vad_can_handle;
    vad_provider.create = onnx_vad_create;
    vad_provider.user_data = nullptr;

    result = rac_service_register_provider(&vad_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
        rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // Unregister service providers
    rac_service_unregister_provider(VAD_PROVIDER_NAME, RAC_CAPABILITY_VAD);
    rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
    rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);

    // Unregister module
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
