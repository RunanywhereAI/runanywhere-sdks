/**
 * @file rac_backend_sdcpp_register.cpp
 * @brief sd.cpp backend registration with the RAC service registry.
 *
 * Implements the rac_diffusion_service_ops_t vtable for sd.cpp,
 * the can_handle/create_service factory pattern, and registration
 * with the service registry for RAC_CAPABILITY_DIFFUSION.
 *
 * Follows the exact same pattern as rac_backend_llamacpp_register.cpp.
 */

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>

#include "rac/backends/rac_diffusion_sdcpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

static const char* LOG_CAT = "Backend.SDCPP.Register";
namespace fs = std::filesystem;

// =============================================================================
// VTABLE IMPLEMENTATION - Adapts rac_diffusion_sdcpp API to vtable interface
// =============================================================================

static rac_result_t sdcpp_vtable_initialize(void* impl, const char* model_path,
                                             const rac_diffusion_config_t* config) {
    return rac_diffusion_sdcpp_load_model(impl, model_path, config);
}

static rac_result_t sdcpp_vtable_generate(void* impl, const rac_diffusion_options_t* options,
                                           rac_diffusion_result_t* out_result) {
    return rac_diffusion_sdcpp_generate(impl, options, out_result);
}

static rac_result_t sdcpp_vtable_generate_with_progress(
    void* impl, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback, void* user_data,
    rac_diffusion_result_t* out_result) {
    return rac_diffusion_sdcpp_generate_with_progress(impl, options, progress_callback, user_data,
                                                       out_result);
}

static rac_result_t sdcpp_vtable_get_info(void* impl, rac_diffusion_info_t* out_info) {
    return rac_diffusion_sdcpp_get_info(impl, out_info);
}

static uint32_t sdcpp_vtable_get_capabilities(void* impl) {
    return rac_diffusion_sdcpp_get_capabilities(impl);
}

static rac_result_t sdcpp_vtable_cancel(void* impl) {
    return rac_diffusion_sdcpp_cancel(impl);
}

static rac_result_t sdcpp_vtable_cleanup(void* impl) {
    return rac_diffusion_sdcpp_unload(impl);
}

static void sdcpp_vtable_destroy(void* impl) { rac_diffusion_sdcpp_destroy(impl); }

/**
 * The vtable for the sd.cpp diffusion backend.
 * This is assigned to every rac_diffusion_service_t created by this backend.
 */
static const rac_diffusion_service_ops_t g_sdcpp_diffusion_ops = {
    .initialize = sdcpp_vtable_initialize,
    .generate = sdcpp_vtable_generate,
    .generate_with_progress = sdcpp_vtable_generate_with_progress,
    .get_info = sdcpp_vtable_get_info,
    .get_capabilities = sdcpp_vtable_get_capabilities,
    .cancel = sdcpp_vtable_cancel,
    .cleanup = sdcpp_vtable_cleanup,
    .destroy = sdcpp_vtable_destroy,
};

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct SdcppRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "SdcppDiffusion";
    char module_id[16] = "sdcpp";
};

static SdcppRegistryState& get_state() {
    static SdcppRegistryState state;
    return state;
}

// =============================================================================
// CAN_HANDLE - Decides if this backend should handle a diffusion request
// =============================================================================

/**
 * Check if the model path contains sd.cpp-compatible model files.
 */
static bool has_sdcpp_model_files(const char* path) {
    if (!path) return false;

    fs::path p(path);

    // Single file check
    if (fs::exists(p) && fs::is_regular_file(p)) {
        std::string ext = p.extension().string();
        return ext == ".safetensors" || ext == ".gguf" || ext == ".ckpt";
    }

    // Directory check
    if (fs::exists(p) && fs::is_directory(p)) {
        try {
            for (const auto& entry : fs::directory_iterator(p)) {
                std::string ext = entry.path().extension().string();
                if (ext == ".safetensors" || ext == ".gguf" || ext == ".ckpt") {
                    return true;
                }
            }
        } catch (const fs::filesystem_error&) {
            // Ignore
        }
    }

    return false;
}

static rac_bool_t sdcpp_can_handle(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return RAC_FALSE;

    // If framework is explicitly set, only handle if it's SDCPP or UNKNOWN
    if (request->framework != RAC_FRAMEWORK_UNKNOWN && request->framework != RAC_FRAMEWORK_SDCPP) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: framework mismatch (%d), rejecting",
                      static_cast<int>(request->framework));
        return RAC_FALSE;
    }

    // If framework is explicitly SDCPP, always accept
    if (request->framework == RAC_FRAMEWORK_SDCPP) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: framework is SDCPP, accepting");
        return RAC_TRUE;
    }

    // Framework is UNKNOWN — check model path for sd.cpp files
    if (request->model_path && has_sdcpp_model_files(request->model_path)) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: found sd.cpp model files at %s", request->model_path);
        return RAC_TRUE;
    }

    // Also check identifier (might be a path)
    if (request->identifier && has_sdcpp_model_files(request->identifier)) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: found sd.cpp model files at %s", request->identifier);
        return RAC_TRUE;
    }

    RAC_LOG_DEBUG(LOG_CAT, "can_handle: no sd.cpp model found, rejecting");
    return RAC_FALSE;
}

// =============================================================================
// CREATE_SERVICE - Factory function
// =============================================================================

static rac_handle_t sdcpp_create_service(const rac_service_request_t* request,
                                          void* /*user_data*/) {
    RAC_LOG_INFO(LOG_CAT, "Creating sd.cpp diffusion service for: %s",
                 request && request->identifier ? request->identifier : "unknown");

    // Create the backend
    rac_handle_t backend = rac_diffusion_sdcpp_create();
    if (!backend) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create sd.cpp backend");
        return nullptr;
    }

    // Allocate service struct with vtable
    auto* service = static_cast<rac_diffusion_service_t*>(
        calloc(1, sizeof(rac_diffusion_service_t)));
    if (!service) {
        rac_diffusion_sdcpp_destroy(backend);
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate service struct");
        return nullptr;
    }

    service->ops = &g_sdcpp_diffusion_ops;
    service->impl = backend;
    service->model_id =
        (request && request->identifier) ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "sd.cpp diffusion service created successfully");
    return static_cast<rac_handle_t>(service);
}

// =============================================================================
// REGISTRATION
// =============================================================================

extern "C" rac_result_t rac_backend_sdcpp_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        RAC_LOG_WARNING(LOG_CAT, "sd.cpp backend already registered");
        return RAC_SUCCESS;
    }

    RAC_LOG_INFO(LOG_CAT, "Registering sd.cpp diffusion backend...");

    // 1. Register as a module
    static const rac_capability_t sdcpp_caps[] = {RAC_CAPABILITY_DIFFUSION};
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = state.provider_name;
    module_info.version = "1.0.0";
    module_info.capabilities = sdcpp_caps;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        RAC_LOG_ERROR(LOG_CAT, "Module registration failed: %d", result);
        return result;
    }

    // 2. Register as a service provider for DIFFUSION capability
    // Priority 90: lower than CoreML (100) so CoreML wins on Apple platforms when both apply,
    // but sd.cpp is used on Android or when model is in safetensors/gguf format.
    rac_service_provider_t provider = {};
    provider.name = state.provider_name;
    provider.capability = RAC_CAPABILITY_DIFFUSION;
    provider.priority = 90;
    provider.can_handle = sdcpp_can_handle;
    provider.create = sdcpp_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Provider registration failed: %d", result);
        return result;
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "sd.cpp diffusion backend registered (priority=90)");

    return RAC_SUCCESS;
}
