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
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "Diffusion.Service";
namespace fs = std::filesystem;

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

/**
 * Detect model format from path by checking for actual model files.
 * Returns the detected framework, or RAC_FRAMEWORK_UNKNOWN if unsure.
 */
static rac_inference_framework_t detect_model_format_from_path(const char* path) {
    if (!path) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    
    fs::path dir_path(path);
    
    if (!fs::exists(dir_path) || !fs::is_directory(dir_path)) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    
    // Check for ONNX diffusion structure (unet/, text_encoder/, vae_decoder/)
    bool has_onnx_unet = fs::exists(dir_path / "unet" / "model.onnx");
    bool has_onnx_text_encoder = fs::exists(dir_path / "text_encoder" / "model.onnx");
    bool has_onnx_vae = fs::exists(dir_path / "vae_decoder" / "model.onnx");
    
    if (has_onnx_unet || has_onnx_text_encoder || has_onnx_vae) {
        RAC_LOG_DEBUG(LOG_CAT, "Detected ONNX diffusion model at path: %s", path);
        return RAC_FRAMEWORK_ONNX;
    }
    
    // Check for .onnx files at root level
    try {
        for (const auto& entry : fs::directory_iterator(dir_path)) {
            if (entry.path().extension() == ".onnx") {
                RAC_LOG_DEBUG(LOG_CAT, "Found .onnx file at root, detected ONNX model");
                return RAC_FRAMEWORK_ONNX;
            }
        }
    } catch (const fs::filesystem_error&) {
        // Ignore
    }
    
    // Check for CoreML files (.mlmodelc, .mlpackage)
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
    } catch (const fs::filesystem_error&) {
        // Ignore
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

    // Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    // If not found by model_id, try looking up by path (model_id might be a path)
    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &model_info);
    }

    // Start with UNKNOWN framework - will be determined by file detection or registry
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    const char* model_path = model_id;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path ? model_info->local_path : model_id;
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL",
                     static_cast<int>(framework), model_path ? model_path : "NULL");
    } else {
        RAC_LOG_WARNING(LOG_CAT,
                        "Model NOT found in registry (result=%d), will detect from path",
                        result);

        // Try to detect framework from the model path/id
        framework = detect_model_format_from_path(model_id);

        if (framework == RAC_FRAMEWORK_UNKNOWN) {
            // If still unknown, use platform defaults
#if defined(__APPLE__)
            framework = RAC_FRAMEWORK_COREML;
            RAC_LOG_INFO(LOG_CAT, "Could not detect format, defaulting to CoreML on Apple");
#else
            framework = RAC_FRAMEWORK_ONNX;
            RAC_LOG_INFO(LOG_CAT, "Could not detect format, defaulting to ONNX");
#endif
        } else {
            RAC_LOG_INFO(LOG_CAT, "Detected framework=%d from path inspection",
                         static_cast<int>(framework));
        }
    }

    if (config &&
        static_cast<rac_inference_framework_t>(config->preferred_framework) !=
            RAC_FRAMEWORK_UNKNOWN) {
        framework = static_cast<rac_inference_framework_t>(config->preferred_framework);
        RAC_LOG_INFO(LOG_CAT, "Using preferred framework override: %d",
                     static_cast<int>(framework));
    }

    // Build service request
    rac_service_request_t request = {};
    request.identifier = model_id;
    request.capability = RAC_CAPABILITY_DIFFUSION;
    request.framework = framework;
    request.model_path = model_path;

    RAC_LOG_INFO(LOG_CAT, "Diffusion service request: framework=%d (%s), model_path=%s",
                 static_cast<int>(request.framework),
                 framework == RAC_FRAMEWORK_COREML ? "CoreML" :
                 framework == RAC_FRAMEWORK_ONNX ? "ONNX" :
                 framework == RAC_FRAMEWORK_UNKNOWN ? "Unknown" : "Other",
                 request.model_path ? request.model_path : "NULL");

    // Service registry returns an rac_diffusion_service_t* with vtable already set
    RAC_LOG_INFO(LOG_CAT, "Calling rac_service_create for DIFFUSION capability...");
    result = rac_service_create(RAC_CAPABILITY_DIFFUSION, &request, out_handle);

    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create service via registry: %d", result);
        return result;
    }

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

rac_result_t rac_diffusion_generate_with_progress(rac_handle_t handle,
                                                  const rac_diffusion_options_t* options,
                                                  rac_diffusion_progress_callback_fn progress_callback,
                                                  void* user_data,
                                                  rac_diffusion_result_t* out_result) {
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

    return service->ops->generate_with_progress(service->impl, options, progress_callback, user_data,
                                                out_result);
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
