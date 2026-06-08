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
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "../common/rac_service_factory_internal.h"

// B-AK-17-003: mirror JNI.RAG and use __android_log_print directly so the
// embeddings creation path is always visible in logcat — the platform
// adapter logging is silent for these categories on Android per
// AK-17-phase6-final-v2.log observations.
#ifdef __ANDROID__
#include <android/log.h>
#define EMBED_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "Embeddings.Service", __VA_ARGS__)
#define EMBED_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "Embeddings.Service", __VA_ARGS__)
#else
#define EMBED_LOGI(...) RAC_LOG_INFO("Embeddings.Service", __VA_ARGS__)
#define EMBED_LOGE(...) RAC_LOG_ERROR("Embeddings.Service", __VA_ARGS__)
#endif

static const char* LOG_CAT = "Embeddings.Service";

namespace {

const rac_embeddings_service_ops_t* embedding_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->embedding_ops : nullptr;
}

}  // namespace

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

static rac_result_t embeddings_create_internal(const char* model_id, const char* config_json,
                                               rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    EMBED_LOGI("Creating embeddings service for: %s", model_id);
    RAC_LOG_INFO(LOG_CAT, "Creating embeddings service for: %s", model_id);

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result = rac::features::resolve_model_reference(
        model_id,
        {.log_cat = LOG_CAT,
         .default_framework = RAC_FRAMEWORK_LLAMACPP,
         .allow_null_model_id = false,
         .lookup_last_path_component = true,
         .prefer_input_path_when_contains = nullptr},
        &model_ref);
    if (result != RAC_SUCCESS) {
        EMBED_LOGE("Model reference resolution failed: result=%d", result);
        return result;
    }

    if (!model_ref.found) {
        size_t path_len = strlen(model_id);
        if (path_len >= 5) {
            const char* ext = model_id + path_len - 5;
            if (strcmp(ext, ".onnx") == 0 || strcmp(ext, ".ONNX") == 0) {
                model_ref.framework = RAC_FRAMEWORK_ONNX;
            }
        }
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry, inferred framework=%d from path",
                        static_cast<int>(model_ref.framework));
    }

    rac_embeddings_service_t* service = nullptr;
    result =
        rac::features::create_plugin_service<rac_embeddings_service_t, rac_embeddings_service_ops_t>(
            {.log_cat = LOG_CAT,
             .primitive = RAC_PRIMITIVE_EMBED,
             .select_ops = embedding_ops,
             .model_create_id = model_ref.path.c_str(),
             .model_id_for_service = model_id,
             .config_json = config_json,
             .created_event_name = "embeddings.backend.created",
             .created_event_category = RAC_EVENT_CATEGORY_MODEL},
            &service);
    if (result != RAC_SUCCESS) {
        EMBED_LOGE("Plugin create failed: result=%d", result);
        return result;
    }

    EMBED_LOGI("Embeddings service created via model_path=%s", model_ref.path.c_str());
    *out_handle = service;

    RAC_LOG_INFO(LOG_CAT, "Embeddings service created");
    return RAC_SUCCESS;
}

rac_result_t rac_embeddings_create(const char* model_id, rac_handle_t* out_handle) {
    return embeddings_create_internal(model_id, nullptr, out_handle);
}

rac_result_t rac_embeddings_create_with_config(const char* model_id, const char* config_json,
                                               rac_handle_t* out_handle) {
    return embeddings_create_internal(model_id, config_json, out_handle);
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
                                        size_t num_texts, const rac_embeddings_options_t* options,
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

}  // extern "C"
