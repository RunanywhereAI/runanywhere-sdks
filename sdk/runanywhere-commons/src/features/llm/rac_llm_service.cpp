/**
 * @file rac_llm_service.cpp
 * @brief LLM Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 * No wrappers, no switch statements - just vtable calls.
 */

#include "rac/features/llm/rac_llm_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "LLM.Service";

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating LLM service for: %s", model_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    // If not found by model_id, try looking up by path (model_id might be a path)
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
    }

    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        const char* reg_path = model_info->local_path ? model_info->local_path : model_id;
        // Registry local_path is often the model directory; LlamaCPP needs the path to the .gguf file.
        // If model_id is already a path to a .gguf file (e.g. from path lookup), use it for loading.
        if (strstr(model_id, ".gguf") != nullptr) {
            model_path = model_id;
        } else {
            model_path = reg_path;
        }
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL",
                     static_cast<int>(framework), model_path ? model_path : "NULL");
    } else {
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), using default framework=%d",
                        result, static_cast<int>(framework));
    }

    // Build service request
    rac_service_request_t request = {};
    request.identifier = model_id;
    request.capability = RAC_CAPABILITY_TEXT_GENERATION;
    request.framework = framework;
    request.model_path = model_path;

    RAC_LOG_INFO(LOG_CAT, "Service request: framework=%d, model_path=%s",
                 static_cast<int>(request.framework),
                 request.model_path ? request.model_path : "NULL");

    // Service registry returns an rac_llm_service_t* with vtable already set
    result = rac_service_create(RAC_CAPABILITY_TEXT_GENERATION, &request, out_handle);

    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry: %d", result);
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "LLM service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                              const rac_llm_options_t* options, rac_llm_result_t* out_result) {
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: START handle=%p, prompt=%p, out_result=%p",
                 handle, (void*)prompt, (void*)out_result);

    if (!handle || !prompt || !out_result) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_generate: NULL pointer!");
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: casting to service...");
    auto* service = static_cast<rac_llm_service_t*>(handle);
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: service=%p, ops=%p", (void*)service, (void*)service->ops);

    if (!service->ops || !service->ops->generate) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_generate: ops or generate is NULL!");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: ops->generate=%p, impl=%p",
                 (void*)service->ops->generate, service->impl);
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: calling backend generate...");

    rac_result_t result = service->ops->generate(service->impl, prompt, options, out_result);

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: backend returned result=%d", result);
    return result;
}

rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                     const rac_llm_options_t* options,
                                     rac_llm_stream_callback_fn callback, void* user_data) {
    if (!handle || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->generate_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->generate_stream(service->impl, prompt, options, callback, user_data);
}

rac_result_t rac_llm_get_info(rac_handle_t handle, rac_llm_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_llm_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->cancel) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cancel(service->impl);
}

rac_result_t rac_llm_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_llm_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_llm_service_t*>(handle);

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

void rac_llm_result_free(rac_llm_result_t* result) {
    if (!result)
        return;
    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
}

}  // extern "C"
