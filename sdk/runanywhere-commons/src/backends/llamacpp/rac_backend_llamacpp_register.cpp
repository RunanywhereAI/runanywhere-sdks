/**
 * @file rac_backend_llamacpp_register.cpp
 * @brief RunAnywhere Core - LlamaCPP Backend Registration
 *
 * Registers the LlamaCPP backend with the module and service registries.
 * Provides vtable implementation for the generic LLM service interface.
 */

#include "rac_llm_llamacpp.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

#include <nlohmann/json.hpp>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"

static const char* LOG_CAT = "LlamaCPP";

// =============================================================================
// VTABLE IMPLEMENTATION - Adapters for generic service interface
// =============================================================================

namespace {

// Initialize (model already loaded during create for LlamaCpp)
static rac_result_t llamacpp_vtable_initialize(void* impl, const char* model_path) {
    return rac_llm_llamacpp_load_model(impl, model_path, nullptr);
}

// Generate (blocking)
static rac_result_t llamacpp_vtable_generate(void* impl, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_result_t* out_result) {
    return rac_llm_llamacpp_generate(impl, prompt, options, out_result);
}

// Streaming callback adapter
struct StreamAdapter {
    rac_llm_stream_callback_fn callback;
    void* user_data;
};

static rac_bool_t stream_adapter_callback(const char* token, rac_bool_t is_final, void* ctx) {
    auto* adapter = static_cast<StreamAdapter*>(ctx);
    (void)is_final;
    if (adapter && adapter->callback) {
        return adapter->callback(token, adapter->user_data);
    }
    return RAC_TRUE;
}

// Generate stream
static rac_result_t llamacpp_vtable_generate_stream(void* impl, const char* prompt,
                                                    const rac_llm_options_t* options,
                                                    rac_llm_stream_callback_fn callback,
                                                    void* user_data) {
    StreamAdapter adapter = {callback, user_data};
    return rac_llm_llamacpp_generate_stream(impl, prompt, options, stream_adapter_callback,
                                            &adapter);
}

// Get info
static rac_result_t llamacpp_vtable_get_info(void* impl, rac_llm_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = rac_llm_llamacpp_is_model_loaded(impl);
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;  // Default if model not loaded or info unavailable

    // Get actual context_length from model info JSON when model is loaded
    if (out_info->is_ready) {
        char* json_str = nullptr;
        if (rac_llm_llamacpp_get_model_info(impl, &json_str) == RAC_SUCCESS && json_str) {
            try {
                auto json = nlohmann::json::parse(json_str);
                if (json.contains("context_size") && json["context_size"].is_number()) {
                    out_info->context_length = json["context_size"].get<int32_t>();
                }
            } catch (...) {
                // JSON parse error - context_length remains 0
            }
            free(json_str);
        }
    }

    return RAC_SUCCESS;
}

// Cancel
static rac_result_t llamacpp_vtable_cancel(void* impl) {
    rac_llm_llamacpp_cancel(impl);
    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t llamacpp_vtable_cleanup(void* impl) {
    return rac_llm_llamacpp_unload_model(impl);
}

// Destroy
static void llamacpp_vtable_destroy(void* impl) {
    rac_llm_llamacpp_destroy(impl);
}

// LoRA adapter management
static rac_result_t llamacpp_vtable_load_lora(void* impl, const char* adapter_path, float scale) {
    return rac_llm_llamacpp_load_lora(impl, adapter_path, scale);
}

static rac_result_t llamacpp_vtable_remove_lora(void* impl, const char* adapter_path) {
    return rac_llm_llamacpp_remove_lora(impl, adapter_path);
}

static rac_result_t llamacpp_vtable_clear_lora(void* impl) {
    return rac_llm_llamacpp_clear_lora(impl);
}

static rac_result_t llamacpp_vtable_get_lora_info(void* impl, char** out_json) {
    return rac_llm_llamacpp_get_lora_info(impl, out_json);
}

static rac_result_t llamacpp_vtable_check_lora_compat(void* impl, const char* lora_path, char** out_error) {
    rac_bool_t result = rac_llm_llamacpp_check_lora_compat(impl, lora_path, out_error);
    return (result == RAC_TRUE) ? RAC_SUCCESS : RAC_ERROR_VALIDATION_FAILED;
}

// Static vtable for LlamaCpp
static const rac_llm_service_ops_t g_llamacpp_ops = {
    .initialize = llamacpp_vtable_initialize,
    .generate = llamacpp_vtable_generate,
    .generate_stream = llamacpp_vtable_generate_stream,
    .get_info = llamacpp_vtable_get_info,
    .cancel = llamacpp_vtable_cancel,
    .cleanup = llamacpp_vtable_cleanup,
    .destroy = llamacpp_vtable_destroy,
    .load_lora = llamacpp_vtable_load_lora,
    .remove_lora = llamacpp_vtable_remove_lora,
    .clear_lora = llamacpp_vtable_clear_lora,
    .get_lora_info = llamacpp_vtable_get_lora_info,
    .check_lora_compat = llamacpp_vtable_check_lora_compat,
};

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct LlamaCPPRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "LlamaCPPService";
    char module_id[16] = "llamacpp";
};

LlamaCPPRegistryState& get_state() {
    static LlamaCPPRegistryState state;
    return state;
}

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATION
// =============================================================================

rac_bool_t llamacpp_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: request is NULL");
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

    // If framework is explicitly set to something else, don't handle
    if (request->framework != RAC_FRAMEWORK_UNKNOWN) {
        RAC_LOG_DEBUG(LOG_CAT,
                      "can_handle: NO (framework mismatch, expected LLAMACPP=%d or UNKNOWN=%d, got %d)",
                      RAC_FRAMEWORK_LLAMACPP, RAC_FRAMEWORK_UNKNOWN, static_cast<int>(request->framework));
        return RAC_FALSE;
    }

    // Framework unknown - check file extension
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
 * Create a LlamaCPP LLM service with vtable.
 * Returns an rac_llm_service_t* that the generic API can dispatch through.
 */
rac_handle_t llamacpp_create_service(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    const char* model_path = request->model_path ? request->model_path : request->identifier;
    if (model_path == nullptr || model_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "No model path provided");
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating LlamaCPP service for: %s", model_path);

    // Create backend-specific handle
    rac_handle_t backend_handle = nullptr;
    rac_result_t result = rac_llm_llamacpp_create(model_path, nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create LlamaCPP backend: %d", result);
        return nullptr;
    }

    // Allocate service struct with vtable
    auto* service = static_cast<rac_llm_service_t*>(malloc(sizeof(rac_llm_service_t)));
    if (!service) {
        rac_llm_llamacpp_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_llamacpp_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "LlamaCPP service created successfully");
    return service;
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_llamacpp_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "LlamaCPP";
    module_info.version = "1.0.0";
    module_info.description = "LLM backend using llama.cpp for GGUF models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_TEXT_GENERATION};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register service provider
    rac_service_provider_t provider = {};
    provider.name = state.provider_name;
    provider.capability = RAC_CAPABILITY_TEXT_GENERATION;
    provider.priority = 100;
    provider.can_handle = llamacpp_can_handle;
    provider.create = llamacpp_create_service;
    provider.user_data = nullptr;

    result = rac_service_register_provider(&provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(state.module_id);
        return result;
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(state.provider_name, RAC_CAPABILITY_TEXT_GENERATION);
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
