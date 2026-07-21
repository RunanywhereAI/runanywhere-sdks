/** @file rac_vocoder_service.cpp @brief Mel vocoder plugin dispatch. */

#include "rac/features/vocoder/rac_vocoder_service.h"

#include "vocoder_service_internal.h"

#include <cstdlib>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Vocoder.Service";

const rac_vocoder_service_ops_t* vocoder_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->vocoder_ops : nullptr;
}

}  // namespace

rac_result_t rac::vocoder::create_service(const char* model_id, const char* config_json,
                                          rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    rac::features::ResolvedModelReference model_ref;
    rac_result_t rc =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = kLogCategory,
                                                .default_framework = RAC_FRAMEWORK_ONNX,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_vocoder_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_vocoder_service_t, rac_vocoder_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_VOCODE,
         .select_ops = vocoder_ops,
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

rac_result_t rac_vocoder_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::vocoder::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_vocoder_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_vocoder_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_vocoder_vocode(rac_handle_t handle, const rac_vocoder_input_t* input,
                                rac_vocoder_result_t* out_result) {
    if (!handle || !input || !input->mel_spectrogram || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_vocoder_service_t*>(handle);
    if (!service->ops || !service->ops->vocode) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    return service->ops->vocode(service->impl, input, out_result);
}

rac_result_t rac_vocoder_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_vocoder_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_vocoder_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_vocoder_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_vocoder_result_free(rac_vocoder_result_t* result) {
    if (!result) {
        return;
    }
    std::free(result->samples);
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"
