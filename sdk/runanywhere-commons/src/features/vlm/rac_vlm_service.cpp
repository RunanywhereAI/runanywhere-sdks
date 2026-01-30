/**
 * @file rac_vlm_service.cpp
 * @brief VLM Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 * No wrappers, no switch statements - just vtable calls.
 */

#include "rac/features/vlm/rac_vlm_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "VLM.Service";

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_vlm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating VLM service for: %s", model_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    // Default to llama.cpp for VLM (has broad VLM support via mtmd)
    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : model_id;
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: framework=%d, local_path=%s",
                     static_cast<int>(framework), model_path ? model_path : "NULL");
    } else {
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), using default framework=%d",
                        result, static_cast<int>(framework));
    }

    // Build service request
    rac_service_request_t request = {};
    request.identifier = model_id;
    request.capability = RAC_CAPABILITY_VISION_LANGUAGE;
    request.framework = framework;
    request.model_path = model_path;

    RAC_LOG_INFO(LOG_CAT, "Service request: framework=%d, model_path=%s",
                 static_cast<int>(request.framework),
                 request.model_path ? request.model_path : "NULL");

    // Service registry returns an rac_vlm_service_t* with vtable already set
    result = rac_service_create(RAC_CAPABILITY_VISION_LANGUAGE, &request, out_handle);

    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry: %d", result);
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "VLM service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_vlm_initialize(rac_handle_t handle, const char* model_path,
                                const char* mmproj_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path, mmproj_path);
}

rac_result_t rac_vlm_process(rac_handle_t handle, const rac_vlm_image_t* image, const char* prompt,
                             const rac_vlm_options_t* options, rac_vlm_result_t* out_result) {
    if (!handle || !image || !prompt || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->process) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->process(service->impl, image, prompt, options, out_result);
}

rac_result_t rac_vlm_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                    const char* prompt, const rac_vlm_options_t* options,
                                    rac_vlm_stream_callback_fn callback, void* user_data) {
    if (!handle || !image || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->process_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->process_stream(service->impl, image, prompt, options, callback, user_data);
}

rac_result_t rac_vlm_get_info(rac_handle_t handle, rac_vlm_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_vlm_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->cancel) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cancel(service->impl);
}

rac_result_t rac_vlm_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_vlm_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_vlm_service_t*>(handle);

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

void rac_vlm_result_free(rac_vlm_result_t* result) {
    if (!result)
        return;
    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
}

}  // extern "C"
