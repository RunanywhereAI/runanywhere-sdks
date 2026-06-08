/**
 * @file rac_diffusion_service.cpp
 * @brief Diffusion Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 * No wrappers, no switch statements - just vtable calls.
 */

#include "rac/features/diffusion/rac_diffusion_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "../common/rac_service_factory_internal.h"

static const char* LOG_CAT = "Diffusion.Service";
namespace fs = std::filesystem;

namespace {

const rac_diffusion_service_ops_t* diffusion_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->diffusion_ops : nullptr;
}

}  // namespace

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

/**
 * Detect model format from path. Only Apple CoreML diffusion is supported.
 * ONNX diffusion is not supported; we only look for CoreML.
 */
static rac_inference_framework_t detect_model_format_from_path(const char* path) {
    if (!path) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    fs::path dir_path(path);
    if (!fs::exists(dir_path) || !fs::is_directory(dir_path)) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    // Only support CoreML (.mlmodelc, .mlpackage) for Apple Stable Diffusion
    try {
        for (const auto& entry : fs::directory_iterator(dir_path)) {
            std::string ext = entry.path().extension().string();
            std::string name = entry.path().filename().string();
            if (ext == ".mlmodelc" || ext == ".mlpackage" ||
                name.find(".mlmodelc") != std::string::npos ||
                name.find(".mlpackage") != std::string::npos) {
                RAC_LOG_DEBUG(LOG_CAT, "Found CoreML model at path: %s", path);
                return RAC_FRAMEWORK_COREML;
            }
        }
    } catch (const fs::filesystem_error&) {  // NOLINT(bugprone-empty-catch)
        // Best-effort detection: a missing/inaccessible directory or
        // permission error is not actionable here — fall through to
        // RAC_FRAMEWORK_UNKNOWN so callers can probe other framework
        // backends.
    }
    return RAC_FRAMEWORK_UNKNOWN;
}

static rac_result_t diffusion_create_service_internal(const char* model_id,
                                                      const rac_diffusion_config_t* config,
                                                      rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    RAC_LOG_INFO(LOG_CAT, "Creating diffusion service for: %s", model_id);

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result = rac::features::resolve_model_reference(
        model_id,
        {.log_cat = LOG_CAT,
         .default_framework = RAC_FRAMEWORK_UNKNOWN,
         .allow_null_model_id = false,
         .lookup_last_path_component = true,
         .prefer_input_path_when_contains = nullptr},
        &model_ref);
    if (result != RAC_SUCCESS) {
        return result;
    }

    rac_inference_framework_t framework = model_ref.framework;
    std::string model_path_owned = model_ref.path;

    if (!model_ref.found) {
        RAC_LOG_WARNING(LOG_CAT, "Model NOT found in registry (result=%d), will detect from path",
                        model_ref.registry_result);

        // Try to detect framework from the model path/id
        framework = detect_model_format_from_path(model_id);

        if (framework == RAC_FRAMEWORK_UNKNOWN) {
            framework = RAC_FRAMEWORK_COREML;
            RAC_LOG_INFO(LOG_CAT, "Could not detect format, defaulting to CoreML (Apple only)");
        } else if (framework == RAC_FRAMEWORK_ONNX) {
            RAC_LOG_WARNING(LOG_CAT,
                            "ONNX diffusion is not supported; only Apple CoreML. Ignoring ONNX.");
            framework = RAC_FRAMEWORK_COREML;
        } else {
            RAC_LOG_INFO(LOG_CAT, "Detected framework=%d from path inspection",
                         static_cast<int>(framework));
        }
    }

    if (config && static_cast<rac_inference_framework_t>(config->preferred_framework) !=
                      RAC_FRAMEWORK_UNKNOWN) {
        framework = static_cast<rac_inference_framework_t>(config->preferred_framework);
        RAC_LOG_INFO(LOG_CAT, "Using preferred framework override: %d",
                     static_cast<int>(framework));
    }

    rac_diffusion_service_t* service = nullptr;
    result =
        rac::features::create_plugin_service<rac_diffusion_service_t, rac_diffusion_service_ops_t>(
            {.log_cat = LOG_CAT,
             .primitive = RAC_PRIMITIVE_DIFFUSION,
             .select_ops = diffusion_ops,
             .model_create_id = model_path_owned.c_str(),
             .model_id_for_service = model_id,
             .config_json = nullptr,
             .created_event_name = "diffusion.backend.created",
             .created_event_category = RAC_EVENT_CATEGORY_MODEL},
            &service);
    if (result != RAC_SUCCESS) {
        return result;
    }
    *out_handle = service;

    RAC_LOG_INFO(LOG_CAT, "Diffusion service created");
    return RAC_SUCCESS;
}

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_diffusion_create(const char* model_id, rac_handle_t* out_handle) {
    return diffusion_create_service_internal(model_id, nullptr, out_handle);
}

rac_result_t rac_diffusion_create_with_config(const char* model_id,
                                              const rac_diffusion_config_t* config,
                                              rac_handle_t* out_handle) {
    return diffusion_create_service_internal(model_id, config, out_handle);
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_diffusion_initialize(rac_handle_t handle, const char* model_path,
                                      const rac_diffusion_config_t* config) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path, config);
}

rac_result_t rac_diffusion_generate(rac_handle_t handle, const rac_diffusion_options_t* options,
                                    rac_diffusion_result_t* out_result) {
    if (!handle || !options || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->generate) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->generate(service->impl, options, out_result);
}

rac_result_t
rac_diffusion_generate_with_progress(rac_handle_t handle, const rac_diffusion_options_t* options,
                                     rac_diffusion_progress_callback_fn progress_callback,
                                     void* user_data, rac_diffusion_result_t* out_result) {
    if (!handle || !options || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->generate_with_progress) {
        // Fall back to non-progress version if available
        if (service->ops && service->ops->generate) {
            return service->ops->generate(service->impl, options, out_result);
        }
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->generate_with_progress(service->impl, options, progress_callback,
                                                user_data, out_result);
}

rac_result_t rac_diffusion_get_info(rac_handle_t handle, rac_diffusion_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

uint32_t rac_diffusion_get_capabilities(rac_handle_t handle) {
    if (!handle)
        return 0;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->get_capabilities) {
        // Return minimal capabilities
        return RAC_DIFFUSION_CAP_TEXT_TO_IMAGE;
    }

    return service->ops->get_capabilities(service->impl);
}

rac_result_t rac_diffusion_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->cancel) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cancel(service->impl);
}

rac_result_t rac_diffusion_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_diffusion_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_diffusion_service_t*>(handle);

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

void rac_diffusion_result_free(rac_diffusion_result_t* result) {
    if (!result)
        return;

    if (result->image_data) {
        free(result->image_data);
        result->image_data = nullptr;
    }

    if (result->error_message) {
        free(result->error_message);
        result->error_message = nullptr;
    }

    result->image_size = 0;
}

}  // extern "C"
