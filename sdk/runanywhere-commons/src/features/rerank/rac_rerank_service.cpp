/** @file rac_rerank_service.cpp @brief Cross-encoder reranking plugin dispatch. */

#include "rac/features/rerank/rac_rerank_service.h"

#include "rerank_service_internal.h"

#include <cstdlib>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Rerank.Service";

const rac_rerank_service_ops_t* rerank_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->rerank_ops : nullptr;
}

}  // namespace

rac_result_t rac::rerank::create_service(const char* model_id, const char* config_json,
                                         rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    rac::features::ResolvedModelReference model_ref;
    rac_result_t rc =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = kLogCategory,
                                                .default_framework = RAC_FRAMEWORK_LLAMACPP,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_rerank_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_rerank_service_t, rac_rerank_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_RERANK,
         .select_ops = rerank_ops,
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

rac_result_t rac_rerank_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::rerank::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_rerank_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_rerank_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_rerank_rerank(rac_handle_t handle, const char* query,
                               const rac_rerank_candidate_t* candidates, size_t candidate_count,
                               const rac_rerank_options_t* options,
                               rac_rerank_result_t* out_result) {
    if (!handle || !query || !out_result || (candidate_count > 0 && !candidates)) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_rerank_service_t*>(handle);
    if (!service->ops || !service->ops->rerank) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    const rac_rerank_options_t defaults = RAC_RERANK_OPTIONS_DEFAULT;
    return service->ops->rerank(service->impl, query, candidates, candidate_count,
                                options ? options : &defaults, out_result);
}

rac_result_t rac_rerank_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_rerank_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_rerank_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_rerank_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_rerank_result_free(rac_rerank_result_t* result) {
    if (!result) {
        return;
    }
    if (result->items) {
        for (size_t i = 0; i < result->item_count; ++i) {
            std::free(result->items[i].id);
        }
    }
    std::free(result->items);
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"
