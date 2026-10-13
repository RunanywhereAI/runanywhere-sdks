/** @file rac_image_embedding_service.cpp @brief Image embedding (`EMBED_IMAGE`) plugin dispatch. */

#include "rac/features/embeddings/rac_image_embedding_service.h"

#include <cstdlib>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "ImageEmbedding.Service";

const rac_image_embedding_service_ops_t* image_embedding_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->image_embedding_ops : nullptr;
}

}  // namespace

extern "C" {

rac_result_t rac_image_embedding_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    // A vision tower is a Core ML bundle, so the default framework is COREML rather than
    // rerank's LLAMACPP: llama.cpp serves no image-embedding primitive at all, so defaulting to
    // it would resolve to an engine that can never satisfy the request.
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

    rac_image_embedding_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_image_embedding_service_t,
                                              rac_image_embedding_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_EMBED_IMAGE,
         .select_ops = image_embedding_ops,
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

rac_result_t rac_image_embedding_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_image_embedding_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_image_embedding_embed(rac_handle_t handle,
                                       const rac_image_embedding_input_t* image,
                                       rac_embeddings_result_t* out_result) {
    if (!handle || !image || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (!image->pixels || image->width == 0 || image->height == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    // Only RGB8 exists today. Validate here rather than in each engine: an unrecognised layout
    // read as RGB8 does not fail, it embeds garbage and returns a well-formed vector.
    if (image->format != RAC_IMAGE_EMBEDDING_FORMAT_RGB8) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto* service = static_cast<rac_image_embedding_service_t*>(handle);
    if (!service->ops || !service->ops->embed_image) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    return service->ops->embed_image(service->impl, image, out_result);
}

rac_result_t rac_image_embedding_get_info(rac_handle_t handle, rac_embeddings_info_t* out_info) {
    if (!handle || !out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_image_embedding_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_image_embedding_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_image_embedding_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_image_embedding_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_image_embedding_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

}  // extern "C"
