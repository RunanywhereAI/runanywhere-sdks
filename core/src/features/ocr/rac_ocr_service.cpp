/** @file rac_ocr_service.cpp @brief OCR (`RAC_PRIMITIVE_OCR`) plugin dispatch. */

#include "rac/features/ocr/rac_ocr_service.h"

#include <cstdlib>
#include <cstring>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "OCR.Service";

const rac_ocr_service_ops_t* ocr_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->ocr_ops : nullptr;
}

/** Shared validation for both read paths: an unrecognised layout read as RGB8 does not fail,
 *  it recognises garbage and returns a well-formed string. Reject it here, once. */
rac_result_t validate_image(const rac_ocr_image_t* img) {
    if (!img->pixels || img->width == 0 || img->height == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (img->format != RAC_OCR_FORMAT_RGB8) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

}  // namespace

extern "C" {

rac_result_t rac_ocr_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    // COREML, for the same reason image embedding defaults there: the OCR models this serves are
    // Core ML bundles, and llama.cpp serves no OCR primitive at all, so defaulting to it would
    // resolve to an engine that can never satisfy the request.
    rac::features::ResolvedModelReference model_ref;
    rac_result_t rc =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = kLogCategory,
                                                .default_framework = RAC_FRAMEWORK_COREML,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_ocr_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_ocr_service_t, rac_ocr_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_OCR,
         .select_ops = ocr_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = model_id,
         .config_json = nullptr,
         .framework = model_ref.framework},
        &service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    *out_handle = service;
    return RAC_SUCCESS;
}

rac_result_t rac_ocr_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_ocr_recognize(rac_handle_t handle, const rac_ocr_image_t* line,
                               rac_ocr_result_t* out_result) {
    if (!handle || !line || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    const rac_result_t v = validate_image(line);
    if (v != RAC_SUCCESS) {
        return v;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    if (!service->ops || !service->ops->recognize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    return service->ops->recognize(service->impl, line, out_result);
}

rac_result_t rac_ocr_read_page(rac_handle_t handle, const rac_ocr_image_t* page,
                               rac_ocr_result_t* out_result) {
    if (!handle || !page || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    const rac_result_t v = validate_image(page);
    if (v != RAC_SUCCESS) {
        return v;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    // A recognizer-only engine leaves this slot NULL and gets NOT_SUPPORTED. It must never fall
    // through to `recognize` on the whole page: that returns a confident line of nonsense which
    // no caller can distinguish from a real read.
    if (!service->ops || !service->ops->read_page) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    return service->ops->read_page(service->impl, page, out_result);
}

rac_result_t rac_ocr_get_info(rac_handle_t handle, rac_ocr_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->get_info(service->impl, out_info);
}

void rac_ocr_result_free(rac_ocr_result_t* result) {
    if (!result) {
        return;
    }
    for (size_t i = 0; i < result->num_regions; ++i) {
        std::free(result->regions[i].text);
    }
    std::free(result->regions);
    // Zero rather than only clearing the pointer: a double free is a realistic caller mistake
    // here, because a page result is naturally passed around between the detect and read steps.
    std::memset(result, 0, sizeof(*result));
}

rac_result_t rac_ocr_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_ocr_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_ocr_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

}  // extern "C"
