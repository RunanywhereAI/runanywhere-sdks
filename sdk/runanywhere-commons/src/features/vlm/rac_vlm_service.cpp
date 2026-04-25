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
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

static const char* LOG_CAT = "VLM.Service";

static const char* framework_to_plugin_name(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_LLAMACPP:           return "llamacpp_vlm";
        case RAC_FRAMEWORK_ONNX:               return "onnx";
        case RAC_FRAMEWORK_METALRT:            return "metalrt";
        default:                               return nullptr;
    }
}

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

    // If not found by model_id, try looking up by path (model_id might be a path)
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
    }

    // If still not found, extract last path component and try as model ID
    if (result != RAC_SUCCESS) {
        const char* last_slash = strrchr(model_id, '/');
        if (last_slash && last_slash[1] != '\0') {
            const char* extracted_id = last_slash + 1;
            RAC_LOG_DEBUG(LOG_CAT, "Trying extracted model ID from path: %s", extracted_id);
            result = rac_get_model(extracted_id, &model_info);
        }
    }

    // Default to llama.cpp for VLM (has broad VLM support via mtmd)
    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : model_id;
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL", static_cast<int>(framework),
                     model_path ? model_path : "NULL");
    } else {
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), using default framework=%d",
                        result, static_cast<int>(framework));
    }

    // v3 Phase B8: route through the plugin registry. VLM config_json
    // is emitted by registry lookups for multi-file VLM models (mmproj_path,
    // etc.) — today we pass nullptr; future PR will wire up config_json
    // from the model_info's extra fields.
    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework);

    const rac_engine_vtable_t* vt = nullptr;
    result = rac_plugin_route(RAC_PRIMITIVE_VLM,
                              /*format=*/0, &hints, &vt);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (result != RAC_SUCCESS || !vt || !vt->vlm_ops || !vt->vlm_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_route failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    result = vt->vlm_ops->create(model_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_vlm_service_t*>(malloc(sizeof(rac_vlm_service_t)));
    if (!service) {
        if (vt->vlm_ops->destroy) vt->vlm_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->vlm_ops;
    service->impl = impl;
    service->model_id = strdup(model_id);
    *out_handle = service;

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
