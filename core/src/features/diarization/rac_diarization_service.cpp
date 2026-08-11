/**
 * @file rac_diarization_service.cpp
 * @brief Generic standalone speaker-diarization service dispatch.
 */

#include "rac/features/diarization/rac_diarization_service.h"

#include "diarization_service_internal.h"

#include <cstdlib>
#include <cstring>

#include "../common/rac_service_factory_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Diarization.Service";

const rac_diarization_service_ops_t* diarization_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->diarization_ops : nullptr;
}

bool has_complete_stream_ops(const rac_diarization_service_ops_t* ops) {
    return ops && ops->stream_create && ops->stream_feed_audio_chunk && ops->stream_destroy;
}

}  // namespace

rac_result_t rac::diarization::create_service(const char* model_id, const char* config_json,
                                              rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    rac::features::ResolvedModelReference model_ref;
    rac_result_t rc =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = kLogCategory,
                                                .default_framework = RAC_FRAMEWORK_UNKNOWN,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_diarization_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_diarization_service_t,
                                              rac_diarization_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_DIARIZE,
         .select_ops = diarization_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = model_id,
         .config_json = config_json,
         .framework = model_ref.framework},
        &service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    *out_handle = service;
    return RAC_SUCCESS;
}

extern "C" {

rac_result_t rac_diarization_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::diarization::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_diarization_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_diarization_diarize(rac_handle_t handle, const float* samples, size_t sample_count,
                                     const rac_diarization_options_t* options,
                                     rac_diarization_result_t* out_result) {
    if (!handle || !samples || sample_count == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!service->ops || !service->ops->diarize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    const rac_diarization_options_t defaults = RAC_DIARIZATION_OPTIONS_DEFAULT;
    return service->ops->diarize(service->impl, samples, sample_count,
                                 options ? options : &defaults, out_result);
}

rac_result_t rac_diarization_stream_create(rac_handle_t handle,
                                           const rac_diarization_options_t* options,
                                           rac_handle_t* out_stream_handle) {
    if (!handle || !out_stream_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_stream_handle = nullptr;
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!has_complete_stream_ops(service->ops)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    const rac_diarization_options_t defaults = RAC_DIARIZATION_OPTIONS_DEFAULT;
    const rac_result_t rc = service->ops->stream_create(
        service->impl, options ? options : &defaults, out_stream_handle);
    if (rc != RAC_SUCCESS) {
        if (*out_stream_handle) {
            (void)service->ops->stream_destroy(service->impl, *out_stream_handle);
            *out_stream_handle = nullptr;
        }
        return rc;
    }
    if (!*out_stream_handle) {
        return RAC_ERROR_INVALID_STATE;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_diarization_stream_feed_audio_chunk(rac_handle_t handle,
                                                     rac_handle_t stream_handle,
                                                     const float* samples, size_t sample_count,
                                                     rac_diarization_stream_callback_t callback,
                                                     void* user_data) {
    if (!handle || !stream_handle || !callback || (sample_count > 0 && !samples)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!has_complete_stream_ops(service->ops)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->stream_feed_audio_chunk(service->impl, stream_handle, samples,
                                                 sample_count, callback, user_data);
}

rac_result_t rac_diarization_stream_destroy(rac_handle_t handle, rac_handle_t stream_handle) {
    if (!handle || !stream_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!has_complete_stream_ops(service->ops)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->stream_destroy(service->impl, stream_handle);
}

rac_result_t rac_diarization_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;
    }
    return service->ops->cleanup(service->impl);
}

void rac_diarization_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_diarization_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_diarization_result_free(rac_diarization_result_t* result) {
    if (!result) {
        return;
    }
    if (result->segments) {
        for (size_t i = 0; i < result->segment_count; ++i) {
            std::free(result->segments[i].speaker_id);
        }
        std::free(result->segments);
    }
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"
