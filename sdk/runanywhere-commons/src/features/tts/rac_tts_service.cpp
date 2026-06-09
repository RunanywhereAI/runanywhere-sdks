/**
 * @file rac_tts_service.cpp
 * @brief TTS Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 */

#include "rac/features/tts/rac_tts_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "../common/rac_service_factory_internal.h"

static const char* LOG_CAT = "TTS.Service";

namespace {

const rac_tts_service_ops_t* tts_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->tts_ops : nullptr;
}

}  // namespace

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

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result = rac::features::resolve_model_reference(
        voice_id,
        {.log_cat = LOG_CAT,
         .default_framework = RAC_FRAMEWORK_ONNX,
         .allow_null_model_id = false,
         .lookup_last_path_component = true,
         .prefer_input_path_when_contains = nullptr},
        &model_ref);
    if (result != RAC_SUCCESS) {
        return result;
    }

    rac_tts_service_t* service = nullptr;
    result = rac::features::create_plugin_service<rac_tts_service_t, rac_tts_service_ops_t>(
        {.log_cat = LOG_CAT,
         .primitive = RAC_PRIMITIVE_SYNTHESIZE,
         .select_ops = tts_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = voice_id,
         .config_json = nullptr},
        &service);
    if (result != RAC_SUCCESS) {
        return result;
    }
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
