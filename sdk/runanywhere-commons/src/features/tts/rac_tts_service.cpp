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
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

static const char* LOG_CAT = "TTS.Service";

// B-AK-13-001 fix: see matching comment in rac_stt_service.cpp.
// RAC_FRAMEWORK_ONNX TTS voices (Piper etc.) are served by the Sherpa-ONNX
// engine plugin, not "onnx" which has no tts_ops.
static const char* framework_to_plugin_name(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_LLAMACPP:           return "llamacpp";
        case RAC_FRAMEWORK_ONNX:               return "sherpa";
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

rac_result_t rac_tts_create(const char* voice_id, rac_handle_t* out_handle) {
    if (!voice_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating TTS service for: %s", voice_id);

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(voice_id, &model_info);

    // If not found by voice_id, try looking up by path (voice_id might be a path)
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", voice_id);
        result = rac_get_model_by_path(voice_id, &model_info);
    }

    // If still not found, extract last path component and try as model ID
    if (result != RAC_SUCCESS) {
        const char* last_slash = strrchr(voice_id, '/');
        if (last_slash && last_slash[1] != '\0') {
            const char* extracted_id = last_slash + 1;
            RAC_LOG_DEBUG(LOG_CAT, "Trying extracted model ID from path: %s", extracted_id);
            result = rac_get_model(extracted_id, &model_info);
        }
    }

    rac_inference_framework_t framework = RAC_FRAMEWORK_ONNX;
    const char* model_path = voice_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : voice_id;
        RAC_LOG_DEBUG(LOG_CAT, "Found model in registry: id=%s, framework=%d",
                      model_info->id ? model_info->id : "NULL", framework);
    }

    // v3 Phase B8: route through the plugin registry.
    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework);

    const rac_engine_vtable_t* vt = nullptr;
    result = rac_plugin_route(RAC_PRIMITIVE_SYNTHESIZE,
                              /*format=*/0, &hints, &vt);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (result != RAC_SUCCESS || !vt || !vt->tts_ops || !vt->tts_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_route failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    result = vt->tts_ops->create(model_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_tts_service_t*>(malloc(sizeof(rac_tts_service_t)));
    if (!service) {
        if (vt->tts_ops->destroy) vt->tts_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->tts_ops;
    service->impl = impl;
    service->model_id = strdup(voice_id);
    *out_handle = service;

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

rac_result_t rac_tts_get_languages(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json)
        return RAC_ERROR_NULL_POINTER;

    *out_json = nullptr;
    auto* service = static_cast<rac_tts_service_t*>(handle);
    if (!service->ops || !service->ops->get_languages) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_languages(service->impl, out_json);
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
