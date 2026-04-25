/**
 * @file rac_backend_llamacpp_vlm_register.cpp
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend Registration
 *
 * Registers the LlamaCPP VLM backend with the module and service registries.
 * Provides vtable implementation for the generic VLM service interface.
 */

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include <nlohmann/json.hpp>

#include "rac/backends/rac_vlm_llamacpp.h"
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
    return rac_vlm_llamacpp_process_stream(impl, image, prompt, options,
                                           vlm_stream_adapter_callback, &adapter);
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
// GAP 02 Phase 8: exposed non-static so rac_plugin_entry_llamacpp_vlm.cpp
// can extern-reference it when filling the unified engine vtable.
// v3 Phase B2: `create` adapter for llama.cpp VLM. Parses the optional
// "mmproj_path" key from config_json (so VLM's 2-path create signature
// maps cleanly into the uniform rac_vlm_service_ops_t::create slot).
// Other VLM config fields (context_size, etc.) will be added here in a
// future PR when the consumer starts supplying typed config.
rac_result_t llamacpp_vlm_create_impl(const char* model_id,
                                      const char* config_json,
                                      void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;

    std::string mmproj_path_owned;
    const char* mmproj_path = nullptr;
    if (config_json && config_json[0] != '\0') {
        try {
            auto json = nlohmann::json::parse(config_json);
            if (json.contains("mmproj_path") && json["mmproj_path"].is_string()) {
                mmproj_path_owned = json["mmproj_path"].get<std::string>();
                mmproj_path = mmproj_path_owned.c_str();
                RAC_LOG_DEBUG(LOG_CAT, "Parsed mmproj_path from config_json: %s", mmproj_path);
            }
        } catch (const std::exception& e) {
            RAC_LOG_WARNING(LOG_CAT,
                            "config_json parse failed (%s); using defaults", e.what());
        }
    }

    RAC_LOG_INFO(LOG_CAT,
                 "llamacpp_vlm_create_impl: model=%s, mmproj=%s",
                 model_id, mmproj_path ? mmproj_path : "(none)");

    rac_handle_t backend_handle = nullptr;
    rac_result_t rc =
        rac_vlm_llamacpp_create(model_id, mmproj_path, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_vlm_llamacpp_create failed: %d", rc);
        return rc;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

}  // namespace (close anon — see B3-parallel note in rac_backend_llamacpp_register.cpp)

extern "C" const rac_vlm_service_ops_t g_llamacpp_vlm_ops = {
    .initialize = llamacpp_vlm_vtable_initialize,
    .process = llamacpp_vlm_vtable_process,
    .process_stream = llamacpp_vlm_vtable_process_stream,
    .get_info = llamacpp_vlm_vtable_get_info,
    .cancel = llamacpp_vlm_vtable_cancel,
    .cleanup = llamacpp_vlm_vtable_cleanup,
    .destroy = llamacpp_vlm_vtable_destroy,
    .create = llamacpp_vlm_create_impl,
};

namespace {  // reopen for the rest of the file

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

// v3 Phase B2: `llamacpp_vlm_can_handle` and `llamacpp_vlm_create_service`
// removed. Model-format gating flows through the router's metadata.formats
// in rac_plugin_entry_llamacpp_vlm.cpp; wrapper allocation moves to
// commons rac_vlm_create() via rac_plugin_route → g_llamacpp_vlm_ops.create
// (llamacpp_vlm_create_impl defined above).

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

    // v3 Phase B2: plugin registration is the registry's job via
    // rac_plugin_entry_llamacpp_vlm(). Module registration is the only
    // remaining side-effect here (app-level capability discovery).
    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "VLM backend registered successfully (module_register only; "
                          "plugin registration via rac_plugin_entry_llamacpp_vlm)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_vlm_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "VLM backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
