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
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

static const char* LOG_CAT = "STT.Service";

// v3 Phase B8: same framework -> plugin-name mapping used in
// rac_llm_service.cpp (and 5 other consumers). Kept in sync by
// convention; if this drifts, add a shared helper in rac_router.h.
static const char* framework_to_plugin_name(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_LLAMACPP:           return "llamacpp";
        case RAC_FRAMEWORK_ONNX:               return "onnx";
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

rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating STT service for: %s", model_path ? model_path : "NULL");

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t reg_result = RAC_ERROR_NOT_FOUND;
    if (model_path) {
        reg_result = rac_get_model(model_path, &model_info);

        if (reg_result != RAC_SUCCESS) {
            RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_path);
            reg_result = rac_get_model_by_path(model_path, &model_info);
        }

        if (reg_result != RAC_SUCCESS) {
            const char* last_slash = strrchr(model_path, '/');
            if (last_slash && last_slash[1] != '\0') {
                const char* extracted_id = last_slash + 1;
                RAC_LOG_DEBUG(LOG_CAT, "Trying extracted model ID from path: %s", extracted_id);
                reg_result = rac_get_model(extracted_id, &model_info);
            }
        }
    }

    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    const char* resolved_path = model_path;

    if (reg_result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        if (model_info->local_path) {
            resolved_path = model_info->local_path;
        }
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d",
                     model_info->id ? model_info->id : "NULL", static_cast<int>(framework));
    }

    // v3 Phase B8: route through the plugin registry.
    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework);

    const rac_engine_vtable_t* vt = nullptr;
    rac_result_t result = rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE,
                                           /*format=*/0, &hints, &vt);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (result != RAC_SUCCESS || !vt || !vt->stt_ops || !vt->stt_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_route failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    result = vt->stt_ops->create(resolved_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_stt_service_t*>(malloc(sizeof(rac_stt_service_t)));
    if (!service) {
        if (vt->stt_ops->destroy) vt->stt_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->stt_ops;
    service->impl = impl;
    service->model_id = model_path ? strdup(model_path) : nullptr;
    *out_handle = service;

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

rac_result_t rac_stt_get_languages(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json)
        return RAC_ERROR_NULL_POINTER;

    *out_json = nullptr;
    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->get_languages) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_languages(service->impl, out_json);
}

rac_result_t rac_stt_detect_language(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                     const rac_stt_options_t* options, char** out_language) {
    if (!handle || !audio_data || !out_language)
        return RAC_ERROR_NULL_POINTER;

    *out_language = nullptr;
    auto* service = static_cast<rac_stt_service_t*>(handle);
    if (!service->ops || !service->ops->detect_language) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->detect_language(service->impl, audio_data, audio_size, options,
                                         out_language);
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
