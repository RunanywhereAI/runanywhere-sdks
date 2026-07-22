/** @file rac_segmentation_service.cpp @brief Semantic segmentation plugin dispatch. */

#include "rac/features/segmentation/rac_segmentation_service.h"

#include "segmentation_service_internal.h"

#include <cstdlib>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Segmentation.Service";

const rac_segmentation_service_ops_t* segmentation_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->segmentation_ops : nullptr;
}

}  // namespace

rac_result_t rac::segmentation::create_service(const char* model_id, const char* config_json,
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

    rac_segmentation_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_segmentation_service_t,
                                              rac_segmentation_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_SEGMENT,
         .select_ops = segmentation_ops,
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

rac_result_t rac_segmentation_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::segmentation::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_segmentation_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_segmentation_segment(rac_handle_t handle, const rac_segmentation_image_t* image,
                                      const rac_segmentation_options_t* options,
                                      rac_segmentation_result_t* out_result) {
    if (!handle || !image || !image->data || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    if (!service->ops || !service->ops->segment) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    const rac_segmentation_options_t defaults = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    return service->ops->segment(service->impl, image, options ? options : &defaults, out_result);
}

rac_result_t rac_segmentation_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_segmentation_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_segmentation_result_free(rac_segmentation_result_t* result) {
    if (!result) {
        return;
    }
    std::free(result->class_mask);
    std::free(result->diagnostic_rgba);
    if (result->class_summaries) {
        for (size_t i = 0; i < result->class_summary_count; ++i) {
            std::free(result->class_summaries[i].label);
        }
    }
    std::free(result->class_summaries);
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"
