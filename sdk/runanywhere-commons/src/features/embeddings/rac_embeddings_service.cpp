/**
 * @file rac_embeddings_service.cpp
 * @brief Embeddings Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend (llama.cpp, ONNX) provides its own vtable when creating a service.
 * Follows the exact same pattern as VLM/LLM/STT/TTS services.
 */

#include "rac/features/embeddings/rac_embeddings_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "Embeddings.Service";

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_embeddings_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating embeddings service for: %s", model_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    // If not found by model_id, try looking up by path
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
    }

    // Default to llama.cpp for embeddings (supports GGUF embedding models)
    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : model_id;
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
    request.capability = RAC_CAPABILITY_EMBEDDINGS;
    request.framework = framework;
    request.model_path = model_path;

    RAC_LOG_INFO(LOG_CAT, "Service request: framework=%d, model_path=%s",
                 static_cast<int>(request.framework),
                 request.model_path ? request.model_path : "NULL");

    // Service registry returns an rac_embeddings_service_t* with vtable already set
    result = rac_service_create(RAC_CAPABILITY_EMBEDDINGS, &request, out_handle);

    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry: %d", result);
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "Embeddings service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_embeddings_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_embeddings_embed(rac_handle_t handle, const char* text,
                                   const rac_embeddings_options_t* options,
                                   rac_embeddings_result_t* out_result) {
    if (!handle || !text || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);
    if (!service->ops || !service->ops->embed) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->embed(service->impl, text, options, out_result);
}

rac_result_t rac_embeddings_embed_batch(rac_handle_t handle, const char* const* texts,
                                         size_t num_texts,
                                         const rac_embeddings_options_t* options,
                                         rac_embeddings_result_t* out_result) {
    if (!handle || !texts || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);
    if (!service->ops || !service->ops->embed_batch) {
        // Fallback: call single embed for each text
        if (service->ops && service->ops->embed) {
            RAC_LOG_DEBUG(LOG_CAT, "No batch embed, falling back to single embed loop");
            // Not ideal but provides compatibility
            return RAC_ERROR_NOT_SUPPORTED;
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->embed_batch(service->impl, texts, num_texts, options, out_result);
}

rac_result_t rac_embeddings_get_info(rac_handle_t handle, rac_embeddings_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_embeddings_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;
    }

    return service->ops->cleanup(service->impl);
}

void rac_embeddings_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_embeddings_service_t*>(handle);

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

#if !defined(_WIN32)
void rac_embeddings_result_free(rac_embeddings_result_t* result) {
    if (!result)
        return;

    if (result->embeddings) {
        for (size_t i = 0; i < result->num_embeddings; i++) {
            if (result->embeddings[i].data) {
                free(result->embeddings[i].data);
                result->embeddings[i].data = nullptr;
            }
        }
        free(result->embeddings);
        result->embeddings = nullptr;
    }

    result->num_embeddings = 0;
    result->dimension = 0;
}
#endif

}  // extern "C"
