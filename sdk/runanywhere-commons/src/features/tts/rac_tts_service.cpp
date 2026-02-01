/**
 * @file rac_tts_service.cpp
 * @brief TTS Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 */

#include "rac/features/tts/rac_tts_service.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "TTS.Service";

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_tts_create(const char* voice_id, rac_handle_t* out_handle) {
    if (!voice_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating TTS service for: %s", voice_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(voice_id, &model_info);

    rac_inference_framework_t framework = RAC_FRAMEWORK_ONNX;
    const char* model_path = voice_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : voice_id;
        RAC_LOG_DEBUG(LOG_CAT, "Found model in registry, framework=%d", framework);
    }

    // Build service request
    rac_service_request_t request = {};
    request.identifier = voice_id;
    request.capability = RAC_CAPABILITY_TTS;
    request.framework = framework;
    request.model_path = model_path;

    RAC_LOG_INFO(LOG_CAT, "TTS service request: identifier='%s', model_path='%s', framework=%d",
                 request.identifier ? request.identifier : "(null)",
                 request.model_path ? request.model_path : "(null)",
                 static_cast<int>(framework));

    // Service registry returns a rac_tts_service_t* with vtable already set
    result = rac_service_create(RAC_CAPABILITY_TTS, &request, out_handle);
    RAC_LOG_INFO(LOG_CAT, "rac_service_create returned: %d", result);

    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry");
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "TTS service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_tts_initialize(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl);
}

rac_result_t rac_tts_synthesize(rac_handle_t handle, const char* text,
                                const rac_tts_options_t* options, rac_tts_result_t* out_result) {
    if (!handle || !text || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->synthesize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->synthesize(service->impl, text, options, out_result);
}

rac_result_t rac_tts_synthesize_stream(rac_handle_t handle, const char* text,
                                       const rac_tts_options_t* options,
                                       rac_tts_stream_callback_t callback, void* user_data) {
    if (!handle || !text || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->synthesize_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->synthesize_stream(service->impl, text, options, callback, user_data);
}

rac_result_t rac_tts_stop(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->stop) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->stop(service->impl);
}

rac_result_t rac_tts_get_info(rac_handle_t handle, rac_tts_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_tts_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;
    }

    return service->ops->cleanup(service->impl);
}

void rac_tts_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_tts_service_t*>(handle);

    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }

    if (service->model_id) {
        free(const_cast<char*>(service->model_id));
    }

    free(service);
}

void rac_tts_result_free(rac_tts_result_t* result) {
    if (!result)
        return;
    if (result->audio_data) {
        free(result->audio_data);
        result->audio_data = nullptr;
    }
}

}  // extern "C"
