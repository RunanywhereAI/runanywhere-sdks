/**
 * @file rac_vlm_service.cpp
 * @brief VLM Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 * No wrappers, no switch statements - just vtable calls.
 */

#include "rac/features/vlm/rac_vlm_service.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "../common/rac_service_factory_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

static const char* LOG_CAT = "VLM.Service";

namespace {

const rac_vlm_service_ops_t* vlm_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->vlm_ops : nullptr;
}

}  // namespace

static std::string json_escape(const char* value) {
    std::string out;
    if (!value)
        return out;
    for (const char* p = value; *p != '\0'; ++p) {
        switch (*p) {
            case '\\':
                out += "\\\\";
                break;
            case '"':
                out += "\\\"";
                break;
            case '\n':
                out += "\\n";
                break;
            case '\r':
                out += "\\r";
                break;
            case '\t':
                out += "\\t";
                break;
            default:
                out.push_back(*p);
                break;
        }
    }
    return out;
}

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_vlm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating VLM service for: %s", model_id);

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = LOG_CAT,
                                                .default_framework = RAC_FRAMEWORK_LLAMACPP,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (result != RAC_SUCCESS) {
        return result;
    }

    std::string model_path_owned = model_ref.path;
    std::string config_json_owned;

    if (model_ref.found && model_ref.model_info) {
        rac_model_path_resolution_t resolution = {};
        rac_result_t path_rc =
            rac_model_paths_resolve_artifact(model_ref.model_info.get(), model_path_owned.c_str(),
                                             /*expected_primary_sha256=*/nullptr, &resolution);
        if (path_rc == RAC_SUCCESS) {
            if (resolution.primary_model_path) {
                model_path_owned = resolution.primary_model_path;
            }
            if (resolution.mmproj_path) {
                config_json_owned =
                    R"({"mmproj_path":")" + json_escape(resolution.mmproj_path) + R"("})";
            }
        }
        rac_model_path_resolution_free(&resolution);
    }

    rac_vlm_service_t* service = nullptr;
    result = rac::features::create_plugin_service<rac_vlm_service_t, rac_vlm_service_ops_t>(
        {.log_cat = LOG_CAT,
         .primitive = RAC_PRIMITIVE_VLM,
         .select_ops = vlm_ops,
         .model_create_id = model_path_owned.c_str(),
         .model_id_for_service = model_id,
         .config_json = config_json_owned.empty() ? nullptr : config_json_owned.c_str()},
        &service);
    if (result != RAC_SUCCESS) {
        return result;
    }
    *out_handle = service;

    RAC_LOG_INFO(LOG_CAT, "VLM service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_vlm_initialize(rac_handle_t handle, const char* model_path,
                                const char* mmproj_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path, mmproj_path);
}

rac_result_t rac_vlm_process(rac_handle_t handle, const rac_vlm_image_t* image, const char* prompt,
                             const rac_vlm_options_t* options, rac_vlm_result_t* out_result) {
    if (!handle || !image || !prompt || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->process) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->process(service->impl, image, prompt, options, out_result);
}

rac_result_t rac_vlm_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                    const char* prompt, const rac_vlm_options_t* options,
                                    rac_vlm_stream_callback_fn callback, void* user_data) {
    if (!handle || !image || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->process_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->process_stream(service->impl, image, prompt, options, callback, user_data);
}

rac_result_t rac_vlm_get_info(rac_handle_t handle, rac_vlm_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_vlm_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->cancel) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cancel(service->impl);
}

rac_result_t rac_vlm_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_vlm_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_vlm_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    // quiesce any in-flight rac_vlm_*_proto
    // entry points before tearing down the backend impl. Defensive
    // mirror of voice_agent.cpp:594.
    rac_vlm_proto_quiesce();

    auto* service = static_cast<rac_vlm_service_t*>(handle);

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

void rac_vlm_result_free(rac_vlm_result_t* result) {
    if (!result)
        return;
    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
}

}  // extern "C"
