/**
 * @file rac_backend_sarvam_register.cpp
 * @brief Sarvam backend registration with module and service registries.
 */

#include "rac_stt_sarvam.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

const char* LOG_CAT = "Sarvam";
const char* const MODULE_ID = "sarvam";
const char* const STT_PROVIDER_NAME = "SarvamSTTService";

// STT vtable: initialize (no-op for cloud backend)
static rac_result_t sarvam_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// STT vtable: transcribe
static rac_result_t sarvam_stt_vtable_transcribe(void* impl, const void* audio_data,
                                                  size_t audio_size,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result) {
    return rac_stt_sarvam_transcribe(impl, audio_data, audio_size, options, out_result);
}

// STT vtable: stream (not supported by Sarvam API)
static rac_result_t sarvam_stt_vtable_transcribe_stream(void* impl, const void* audio_data,
                                                         size_t audio_size,
                                                         const rac_stt_options_t* options,
                                                         rac_stt_stream_callback_t callback,
                                                         void* user_data) {
    (void)impl;
    (void)audio_data;
    (void)audio_size;
    (void)options;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_NOT_SUPPORTED;
}

// STT vtable: get info
static rac_result_t sarvam_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    (void)impl;
    if (!out_info) return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = RAC_FALSE;
    out_info->current_model = "saarika:v2";
    return RAC_SUCCESS;
}

// STT vtable: cleanup
static rac_result_t sarvam_stt_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// STT vtable: destroy
static void sarvam_stt_vtable_destroy(void* impl) {
    if (impl) {
        rac_stt_sarvam_destroy(impl);
    }
}

static const rac_stt_service_ops_t g_sarvam_stt_ops = {
    .initialize = sarvam_stt_vtable_initialize,
    .transcribe = sarvam_stt_vtable_transcribe,
    .transcribe_stream = sarvam_stt_vtable_transcribe_stream,
    .get_info = sarvam_stt_vtable_get_info,
    .cleanup = sarvam_stt_vtable_cleanup,
    .destroy = sarvam_stt_vtable_destroy,
};

// Provider: can_handle
rac_bool_t sarvam_stt_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (!request) return RAC_FALSE;

    // Match by framework hint
    if (request->framework == RAC_FRAMEWORK_SARVAM) {
        return RAC_TRUE;
    }

    // Match by identifier containing "sarvam"
    if (request->identifier && strstr(request->identifier, "sarvam") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

// Provider: create service
rac_handle_t sarvam_stt_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;
    (void)request;

    RAC_LOG_INFO(LOG_CAT, "Creating Sarvam STT service");

    rac_handle_t backend_handle = nullptr;
    rac_result_t result = rac_stt_sarvam_create(nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service: %d", result);
        return nullptr;
    }

    auto* service = static_cast<rac_stt_service_t*>(malloc(sizeof(rac_stt_service_t)));
    if (!service) {
        rac_stt_sarvam_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_sarvam_stt_ops;
    service->impl = backend_handle;
    service->model_id = request && request->identifier ? strdup(request->identifier) : strdup("sarvam:saarika:v2");

    RAC_LOG_INFO(LOG_CAT, "STT service created successfully");
    return service;
}

bool g_registered = false;

}  // namespace

extern "C" {

rac_result_t rac_backend_sarvam_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "Sarvam AI";
    module_info.version = "1.0.0";
    module_info.description = "Cloud STT backend via Sarvam AI API";
    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register STT provider (lower priority than local backends)
    rac_service_provider_t stt_provider = {};
    stt_provider.name = STT_PROVIDER_NAME;
    stt_provider.capability = RAC_CAPABILITY_STT;
    stt_provider.priority = 10;
    stt_provider.can_handle = sarvam_stt_can_handle;
    stt_provider.create = sarvam_stt_create;

    result = rac_service_register_provider(&stt_provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "Sarvam backend registered (STT)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_sarvam_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    RAC_LOG_INFO(LOG_CAT, "Sarvam backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
