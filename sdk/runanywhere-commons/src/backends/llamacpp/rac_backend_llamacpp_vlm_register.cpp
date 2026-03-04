/**
 * @file rac_backend_llamacpp_vlm_register.cpp
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend Registration
 *
 * Registers the LlamaCPP VLM backend with the module and service registries.
 * Provides vtable implementation for the generic VLM service interface.
 */

#include "rac/backends/rac_vlm_llamacpp.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/vlm/rac_vlm_service.h"

static const char* LOG_CAT = "VLM.LlamaCPP";

// =============================================================================
// VTABLE IMPLEMENTATION - Adapters for generic VLM service interface
// =============================================================================

namespace {

// Initialize with model paths
static rac_result_t llamacpp_vlm_vtable_initialize(void* impl, const char* model_path,
                                                   const char* mmproj_path) {
    return rac_vlm_llamacpp_load_model(impl, model_path, mmproj_path, nullptr);
}

// Process image (blocking)
static rac_result_t llamacpp_vlm_vtable_process(void* impl, const rac_vlm_image_t* image,
                                                const char* prompt,
                                                const rac_vlm_options_t* options,
                                                rac_vlm_result_t* out_result) {
    return rac_vlm_llamacpp_process(impl, image, prompt, options, out_result);
}

// Streaming callback adapter
struct VLMStreamAdapter {
    rac_vlm_stream_callback_fn callback;
    void* user_data;
};

static rac_bool_t vlm_stream_adapter_callback(const char* token, rac_bool_t is_final, void* ctx) {
    auto* adapter = static_cast<VLMStreamAdapter*>(ctx);
    (void)is_final;
    if (adapter && adapter->callback) {
        return adapter->callback(token, adapter->user_data);
    }
    return RAC_TRUE;
}

// Process stream
static rac_result_t llamacpp_vlm_vtable_process_stream(void* impl, const rac_vlm_image_t* image,
                                                       const char* prompt,
                                                       const rac_vlm_options_t* options,
                                                       rac_vlm_stream_callback_fn callback,
                                                       void* user_data) {
    VLMStreamAdapter adapter = {callback, user_data};
    return rac_vlm_llamacpp_process_stream(impl, image, prompt, options, vlm_stream_adapter_callback,
                                           &adapter);
}

// Get info
static rac_result_t llamacpp_vlm_vtable_get_info(void* impl, rac_vlm_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = rac_vlm_llamacpp_is_model_loaded(impl);
    out_info->supports_streaming = RAC_TRUE;
    out_info->supports_multiple_images = RAC_FALSE;  // Current implementation: single image
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    out_info->vision_encoder_type = "clip";  // Default for llama.cpp VLM

    // Get actual info from model
    if (out_info->is_ready) {
        char* json_str = nullptr;
        if (rac_vlm_llamacpp_get_model_info(impl, &json_str) == RAC_SUCCESS && json_str) {
            // Simple parse for context_size
            // In production, use proper JSON parsing
            const char* ctx_key = "\"context_size\":";
            const char* ctx_pos = strstr(json_str, ctx_key);
            if (ctx_pos) {
                out_info->context_length = atoi(ctx_pos + strlen(ctx_key));
            }
            free(json_str);
        }
    }

    return RAC_SUCCESS;
}

// Cancel
static rac_result_t llamacpp_vlm_vtable_cancel(void* impl) {
    rac_vlm_llamacpp_cancel(impl);
    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t llamacpp_vlm_vtable_cleanup(void* impl) {
    return rac_vlm_llamacpp_unload_model(impl);
}

// Destroy
static void llamacpp_vlm_vtable_destroy(void* impl) {
    rac_vlm_llamacpp_destroy(impl);
}

// Static vtable for LlamaCpp VLM
static const rac_vlm_service_ops_t g_llamacpp_vlm_ops = {
    .initialize = llamacpp_vlm_vtable_initialize,
    .process = llamacpp_vlm_vtable_process,
    .process_stream = llamacpp_vlm_vtable_process_stream,
    .get_info = llamacpp_vlm_vtable_get_info,
    .cancel = llamacpp_vlm_vtable_cancel,
    .cleanup = llamacpp_vlm_vtable_cleanup,
    .destroy = llamacpp_vlm_vtable_destroy,
};

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct LlamaCPPVLMRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "LlamaCPPVLMService";
    char module_id[16] = "llamacpp_vlm";
};

LlamaCPPVLMRegistryState& get_state() {
    static LlamaCPPVLMRegistryState state;
    return state;
}

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

/**
 * Check if this backend can handle the service request.
 */
rac_bool_t llamacpp_vlm_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: request is NULL");
        return RAC_FALSE;
    }

    // Must be VISION_LANGUAGE capability
    if (request->capability != RAC_CAPABILITY_VISION_LANGUAGE) {
        return RAC_FALSE;
    }

    RAC_LOG_DEBUG(LOG_CAT, "can_handle: framework=%d, model_path=%s, identifier=%s",
                  static_cast<int>(request->framework),
                  request->model_path ? request->model_path : "NULL",
                  request->identifier ? request->identifier : "NULL");

    // Framework hint from model registry
    if (request->framework == RAC_FRAMEWORK_LLAMACPP) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: YES (framework match)");
        return RAC_TRUE;
    }

    // If framework is explicitly set to something else (not unknown), don't handle
    if (request->framework != RAC_FRAMEWORK_UNKNOWN) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: NO (framework mismatch)");
        return RAC_FALSE;
    }

    // Framework unknown - check file extension for GGUF
    const char* path = request->model_path ? request->model_path : request->identifier;
    if (path == nullptr || path[0] == '\0') {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: NO (no path)");
        return RAC_FALSE;
    }

    size_t len = strlen(path);
    if (len >= 5) {
        const char* ext = path + len - 5;
        if (strcmp(ext, ".gguf") == 0 || strcmp(ext, ".GGUF") == 0) {
            RAC_LOG_DEBUG(LOG_CAT, "can_handle: YES (gguf extension)");
            return RAC_TRUE;
        }
    }

    RAC_LOG_DEBUG(LOG_CAT, "can_handle: NO (no gguf extension in path: %s)", path);
    return RAC_FALSE;
}

/**
 * Create a LlamaCPP VLM service with vtable.
 */
rac_handle_t llamacpp_vlm_create_service(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    const char* model_path = request->model_path ? request->model_path : request->identifier;
    if (model_path == nullptr || model_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "No model path provided");
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating LlamaCPP VLM service for: %s", model_path);

    // Create backend-specific handle
    rac_handle_t backend_handle = nullptr;
    rac_result_t result = rac_vlm_llamacpp_create(model_path, nullptr, nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create LlamaCPP VLM backend: %d", result);
        return nullptr;
    }

    // Allocate service struct with vtable
    auto* service = static_cast<rac_vlm_service_t*>(malloc(sizeof(rac_vlm_service_t)));
    if (!service) {
        rac_vlm_llamacpp_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_llamacpp_vlm_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "LlamaCPP VLM service created successfully");
    return service;
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_llamacpp_vlm_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "LlamaCPP VLM";
    module_info.version = "1.0.0";
    module_info.description = "VLM backend using llama.cpp for GGUF vision-language models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_VISION_LANGUAGE};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register service provider with priority 100 (same as LLM llamacpp)
    rac_service_provider_t provider = {};
    provider.name = state.provider_name;
    provider.capability = RAC_CAPABILITY_VISION_LANGUAGE;
    provider.priority = 100;
    provider.can_handle = llamacpp_vlm_can_handle;
    provider.create = llamacpp_vlm_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(state.module_id);
        return result;
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "VLM backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_vlm_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(state.provider_name, RAC_CAPABILITY_VISION_LANGUAGE);
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "VLM backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
