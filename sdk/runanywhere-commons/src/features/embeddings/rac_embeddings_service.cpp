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
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

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

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    // If not found by model_id, try looking up by path
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
    }

    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    // Own the resolved path as a std::string so it survives
    // rac_model_info_free() below. Previously we captured a raw pointer into
    // model_info->local_path and then freed model_info before
    // vt->embedding_ops->create() — a use-after-free that fed garbage bytes
    // into the ONNX embedding provider's vocab.txt resolver on the second+
    // pipeline create (first call happened to succeed because heap bytes
    // were still intact).
    std::string model_path_owned = model_id ? model_id : "";

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        if (model_info->local_path && model_info->local_path[0] != '\0') {
            model_path_owned = model_info->local_path;
        }
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL", static_cast<int>(framework),
                     model_path_owned.c_str());
    } else {
        // Model not in registry — infer framework from file extension
        // so the correct service provider handles it (ONNX for .onnx files).
        size_t path_len = model_id ? strlen(model_id) : 0;
        if (path_len >= 5) {
            const char* ext = model_id + path_len - 5;
            if (strcmp(ext, ".onnx") == 0 || strcmp(ext, ".ONNX") == 0) {
                framework = RAC_FRAMEWORK_ONNX;
            }
        }
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), inferred framework=%d from path",
                        result, static_cast<int>(framework));
    }

    // v3 Phase B8: route through the plugin registry. Unlike other
    // primitives, embeddings consumer PRESERVES the config_json
    // parameter — the ONNX embeddings provider parses it for dim,
    // pooling, and tokenizer fields (see
    // engines/onnx/onnx_embedding_provider constructor).
    const rac_engine_vtable_t* vt = rac_plugin_find(RAC_PRIMITIVE_EMBED);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (!vt || !vt->embedding_ops || !vt->embedding_ops->create) {
        EMBED_LOGE("no plugin serves EMBED: vt=%p emb_ops=%p", (void*)vt,
                   vt ? (void*)vt->embedding_ops : nullptr);
        RAC_LOG_ERROR(LOG_CAT, "no registered plugin serves EMBED");
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }
    EMBED_LOGI("Routed to plugin: %s (model_path=%s)", vt->metadata.name, model_path_owned.c_str());
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    result = vt->embedding_ops->create(model_path_owned.c_str(), config_json, &impl);
    if (result != RAC_SUCCESS || !impl) {
        EMBED_LOGE("Plugin create failed: result=%d impl=%p", result, impl);
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service =
        static_cast<rac_embeddings_service_t*>(malloc(sizeof(rac_embeddings_service_t)));
    if (!service) {
        if (vt->embedding_ops->destroy)
            vt->embedding_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->embedding_ops;
    service->impl = impl;
    service->model_id = strdup(model_id);
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
