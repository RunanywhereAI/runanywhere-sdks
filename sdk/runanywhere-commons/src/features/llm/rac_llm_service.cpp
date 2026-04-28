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

#ifdef __ANDROID__
#include <android/log.h>
#define ALOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "RAC_LLM_SVC", __VA_ARGS__)
#else
#define ALOGD(...) fprintf(stderr, __VA_ARGS__)
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

static const char* LOG_CAT = "LLM.Service";

// Phase 2.6 (engine independence refactor): identity stringify of the
// framework enum to the plugin's metadata.name. Kept identical to the
// matching helpers in rac_stt_service.cpp / rac_tts_service.cpp /
// rac_embeddings_service.cpp; if this drifts, move to a shared header
// in rac/router/. Returning NULL = no pin (router picks by format/priority).
static const char* framework_to_plugin_name(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_LLAMACPP:           return "llamacpp";
        case RAC_FRAMEWORK_ONNX:               return "onnx";
        case RAC_FRAMEWORK_SHERPA:             return "sherpa";
        case RAC_FRAMEWORK_WHISPERKIT_COREML:  return "whisperkit_coreml";
        case RAC_FRAMEWORK_METALRT:            return "metalrt";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:  return "platform";
        case RAC_FRAMEWORK_SYSTEM_TTS:         return "platform";
        case RAC_FRAMEWORK_COREML:             return "platform";
        default:                               return nullptr;
    }
}

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    ALOGD("rac_llm_create: model_id=%s", model_id);
    RAC_LOG_INFO(LOG_CAT, "Creating LLM service for: %s", model_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);
    ALOGD("rac_get_model result=%d", result);

    // If not found by model_id, try looking up by path (model_id might be a path)
    if (result != RAC_SUCCESS) {
        ALOGD("Trying path lookup: %s", model_id);
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
        ALOGD("rac_get_model_by_path result=%d", result);
    }

    // If still not found, extract last path component and try as model ID
    // (lifecycle passes filesystem path, but registry stores by model ID)
    if (result != RAC_SUCCESS) {
        const char* last_slash = strrchr(model_id, '/');
        if (last_slash && last_slash[1] != '\0') {
            const char* extracted_id = last_slash + 1;
            RAC_LOG_DEBUG(LOG_CAT, "Trying extracted model ID from path: %s", extracted_id);
            result = rac_get_model(extracted_id, &model_info);
        }
    }

    rac_inference_framework_t framework = RAC_FRAMEWORK_LLAMACPP;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        const char* reg_path = model_info->local_path ? model_info->local_path : model_id;
        // Registry local_path is often the model directory; LlamaCPP needs the path to the .gguf
        // file. If model_id is already a path to a .gguf file (e.g. from path lookup), use it for
        // loading.
        if (strstr(model_id, ".gguf") != nullptr) {
            model_path = model_id;
        } else {
            model_path = reg_path;
        }
        ALOGD("Found in registry: id=%s, framework=%d, local_path=%s",
              model_info->id ? model_info->id : "NULL", static_cast<int>(framework),
              model_path ? model_path : "NULL");
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL", static_cast<int>(framework),
                     model_path ? model_path : "NULL");
    } else {
        ALOGD("NOT found in registry (result=%d), default framework=%d", result,
              static_cast<int>(framework));
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), using default framework=%d",
                        result, static_cast<int>(framework));
    }

    // v3 Phase B8: Route through the unified plugin registry instead of the
    // deleted rac_service_create path. framework -> plugin-name pin is a
    // HINT; the router may still fall back to any primitive-compatible
    // plugin if the pinned one is unavailable (e.g. when the app
    // launched without linking the specific engine binary).
    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework);

    const rac_engine_vtable_t* vt = nullptr;
    result = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT,
                              /*format=*/0,  /* no format hint; rely on framework pin */
                              &hints, &vt);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (result != RAC_SUCCESS || !vt || !vt->llm_ops || !vt->llm_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_route failed: %d (vt=%p, llm_ops.create=%p)",
                      result, (const void*)vt,
                      vt ? (const void*)vt->llm_ops : nullptr);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    // Allocate backend impl via the plugin's create adapter.
    void* impl = nullptr;
    result = vt->llm_ops->create(model_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    // Wrap impl in rac_llm_service_t (the generic vtable + impl handle).
    auto* service = static_cast<rac_llm_service_t*>(malloc(sizeof(rac_llm_service_t)));
    if (!service) {
        if (vt->llm_ops->destroy) vt->llm_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->llm_ops;
    service->impl = impl;
    service->model_id = strdup(model_id);
    *out_handle = service;

    ALOGD("LLM service created successfully");
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
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: START handle=%p, prompt=%p, out_result=%p", handle,
                 (void*)prompt, (void*)out_result);

    if (!handle || !prompt || !out_result) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_generate: NULL pointer!");
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: casting to service...");
    auto* service = static_cast<rac_llm_service_t*>(handle);
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: service=%p, ops=%p", (void*)service,
                 (void*)service->ops);

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

rac_result_t rac_llm_generate_stream_with_timing(rac_handle_t handle, const char* prompt,
                                                 const rac_llm_options_t* options,
                                                 rac_llm_stream_callback_fn callback,
                                                 void* user_data,
                                                 rac_benchmark_timing_t* timing_out) {
    if (!handle || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // If backend implements timing-aware streaming, use it
    if (service->ops->generate_stream_with_timing) {
        return service->ops->generate_stream_with_timing(service->impl, prompt, options, callback,
                                                         user_data, timing_out);
    }

    // Fallback to regular streaming for backends that don't implement timing.
    // Backend timestamps (t2/t3/t5) will remain 0 from rac_benchmark_timing_init().
    // The component layer (llm_component.cpp) is responsible for setting t0/t4/t6
    // and the final status/error_code regardless of which path is taken here.
    if (service->ops->generate_stream) {
        return service->ops->generate_stream(service->impl, prompt, options, callback, user_data);
    }

    return RAC_ERROR_NOT_SUPPORTED;
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

// =============================================================================
// ADAPTIVE CONTEXT API - VTable dispatch
// =============================================================================

rac_result_t rac_llm_inject_system_prompt(rac_handle_t handle, const char* prompt) {
    if (!handle || !prompt)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->inject_system_prompt)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->inject_system_prompt(service->impl, prompt);
}

rac_result_t rac_llm_append_context(rac_handle_t handle, const char* text) {
    if (!handle || !text)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->append_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->append_context(service->impl, text);
}

rac_result_t rac_llm_generate_from_context(rac_handle_t handle, const char* query,
                                           const rac_llm_options_t* options,
                                           rac_llm_result_t* out_result) {
    if (!handle || !query || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->generate_from_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->generate_from_context(service->impl, query, options, out_result);
}

rac_result_t rac_llm_clear_context(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->clear_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->clear_context(service->impl);
}

}  // extern "C"
