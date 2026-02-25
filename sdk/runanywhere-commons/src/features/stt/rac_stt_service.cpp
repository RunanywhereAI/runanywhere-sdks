/**
 * @file rac_stt_service.cpp
 * @brief STT Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 */

#include "rac/features/stt/rac_stt_service.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "STT.Service";

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating STT service");

    // Build service request
    rac_service_request_t request = {};
    request.identifier = model_path;
    request.capability = RAC_CAPABILITY_STT;
    request.framework = RAC_FRAMEWORK_UNKNOWN;  // Let service registry dispatch via can_handle
    request.model_path = model_path;

    // Service registry returns an rac_stt_service_t* with vtable already set
    rac_result_t result = rac_service_create(RAC_CAPABILITY_STT, &request, out_handle);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry");
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "STT service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_stt_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_stt_transcribe(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                const rac_stt_options_t* options, rac_stt_result_t* out_result) {
    if (!handle || !audio_data || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->transcribe) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->transcribe(service->impl, audio_data, audio_size, options, out_result);
}

rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                       size_t audio_size, const rac_stt_options_t* options,
                                       rac_stt_stream_callback_t callback, void* user_data) {
    if (!handle || !audio_data || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->transcribe_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->transcribe_stream(service->impl, audio_data, audio_size, options, callback,
                                           user_data);
}

rac_result_t rac_stt_get_info(rac_handle_t handle, rac_stt_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_stt_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_stt_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_stt_service_t*>(handle);

    // Call backend destroy
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }

    // Free model_id if allocated
    if (service->model_id) {
        free(const_cast<char*>(service->model_id));
    }

    // Free service struct
    free(service);
}

void rac_stt_result_free(rac_stt_result_t* result) {
    if (!result)
        return;
    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
    if (result->detected_language) {
        free(result->detected_language);
        result->detected_language = nullptr;
    }
    if (result->words) {
        for (size_t i = 0; i < result->num_words; i++) {
            if (result->words[i].text) {
                free(const_cast<char*>(result->words[i].text));
            }
        }
        free(result->words);
        result->words = nullptr;
        result->num_words = 0;
    }
}

}  // extern "C"
