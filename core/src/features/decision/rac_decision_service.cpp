/** @file rac_decision_service.cpp @brief Decision-model plugin dispatch. */

#include "rac/features/decision/rac_decision_service.h"

#include "decision_service_internal.h"

#include <cstdlib>

#include "../common/rac_service_factory_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Decision.Service";

const rac_decision_service_ops_t* decision_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->decision_ops : nullptr;
}

}  // namespace

rac_result_t rac::decision::create_service(const char* model_id, const char* config_json,
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

    rac_decision_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_decision_service_t, rac_decision_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_DECIDE,
         .select_ops = decision_ops,
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

rac_result_t rac_decision_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::decision::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_decision_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_decision_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_decision_decide(rac_handle_t handle, const char* state,
                                 const rac_decision_question_t* questions, size_t question_count,
                                 const rac_decision_options_t* options,
                                 rac_decision_result_t* out_result) {
    if (!handle || !state || !out_result || (question_count > 0 && !questions)) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_decision_service_t*>(handle);
    if (!service->ops || !service->ops->decide) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    const rac_decision_options_t defaults = RAC_DECISION_OPTIONS_DEFAULT;
    return service->ops->decide(service->impl, state, questions, question_count,
                                options ? options : &defaults, out_result);
}

rac_result_t rac_decision_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_decision_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_decision_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_decision_service_t*>(handle);
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_decision_result_free(rac_decision_result_t* result) {
    if (!result) {
        return;
    }
    if (result->answers) {
        for (size_t i = 0; i < result->answer_count; ++i) {
            std::free(result->answers[i].id);
            std::free(result->answers[i].choice);
            std::free(result->answers[i].probabilities);
            if (result->answers[i].legend) {
                // legend entries are borrowed from the request questions; only
                // the array itself is owned
                std::free(result->answers[i].legend);
            }
        }
    }
    std::free(result->answers);
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"