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
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

static const char* LOG_CAT = "Diffusion.Service";
namespace fs = std::filesystem;

static const char* framework_to_plugin_name(rac_inference_framework_t fw) {
    switch (fw) {
        // Align with the lifecycle mapping in
        // model_lifecycle.cpp (INFERENCE_FRAMEWORK_COREML → "platform") and
        // with the Swift / Flutter reference, both of which only register
        // rac_plugin_entry_platform() — the unified Apple platform vtable
        // that owns g_platform_diffusion_ops (see
        // rac_plugin_entry_platform.cpp:75).
        //
        // The standalone engines/diffusion-coreml/rac_plugin_entry_diffusion_coreml.cpp
        // exists as an opt-in plugin for hosts that prefer the dedicated
        // CoreML diffusion vtable, but no SDK currently registers it. Pinning
        // the engine name to "diffusion_coreml" here would cause the engine
        // router (rac_engine_router.cpp:185-189) to hard-reject the platform
        // vtable that Swift/Flutter actually load, returning
        // RAC_ERROR_BACKEND_NOT_FOUND for every direct CoreML diffusion
        // creation through this service — splitting public diffusion
        // behavior between the lifecycle path (which routes via "platform")
        // and the direct-service path (which used to route via
        // "diffusion_coreml").
        case RAC_FRAMEWORK_COREML:
            return "platform";
        // ONNX diffusion is not supported; leave the hint blank so the
        // router fails cleanly with RAC_ERROR_BACKEND_NOT_FOUND when no
        // plugin advertises diffusion_ops for ONNX.
        case RAC_FRAMEWORK_ONNX:
        default:
            return nullptr;
    }
}

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
    // Own the resolved path as a std::string so it survives rac_model_info_free()
    // below. Previously we captured a raw pointer into model_info->local_path
    // and then freed model_info before vt->diffusion_ops->create() — a
    // use-after-free that handed freed heap bytes to the CoreML diffusion
    // backend (mirrors the embeddings/VLM lifetime fix in the same wave).
    std::string model_path_owned = model_id ? model_id : "";

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        if (model_info->local_path && model_info->local_path[0] != '\0') {
            model_path_owned = model_info->local_path;
        }
        RAC_LOG_INFO(LOG_CAT, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     model_info->id ? model_info->id : "NULL", static_cast<int>(framework),
                     model_path_owned.c_str());
    } else {
        RAC_LOG_WARNING(LOG_CAT, "Model NOT found in registry (result=%d), will detect from path",
                        result);

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

    // Route through the plugin registry.
    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework);

    // Pass the model format hint so the engine
    // router awards kModelFormatWeight to vtables that advertise COREML
    // (the platform vtable in rac_plugin_entry_platform.cpp declares
    // RAC_MODEL_FORMAT_ID_COREML), letting it win the diffusion route even
    // when the engine name hint is left blank.
    uint32_t format_hint = 0;
    if (framework == RAC_FRAMEWORK_COREML) {
        format_hint = RAC_MODEL_FORMAT_ID_COREML;
    } else if (framework == RAC_FRAMEWORK_ONNX) {
        format_hint = RAC_MODEL_FORMAT_ID_ONNX;
    }

    const rac_engine_vtable_t* vt = nullptr;
    result = rac_plugin_route(RAC_PRIMITIVE_DIFFUSION, format_hint, &hints, &vt);
    if (model_info) {
        rac_model_info_free(model_info);
        model_info = nullptr;
    }
    if (result != RAC_SUCCESS || !vt || !vt->diffusion_ops || !vt->diffusion_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_route failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    result = vt->diffusion_ops->create(model_path_owned.c_str(), /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_diffusion_service_t*>(malloc(sizeof(rac_diffusion_service_t)));
    if (!service) {
        if (vt->diffusion_ops->destroy)
            vt->diffusion_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->diffusion_ops;
    service->impl = impl;
    service->model_id = strdup(model_id);
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
