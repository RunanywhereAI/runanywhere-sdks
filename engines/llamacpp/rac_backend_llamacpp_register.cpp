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

// Generate stream with benchmark timing
static rac_result_t llamacpp_vtable_generate_stream_with_timing(
    void* impl, const char* prompt, const rac_llm_options_t* options,
    rac_llm_stream_callback_fn callback, void* user_data, rac_benchmark_timing_t* timing_out) {
    StreamAdapter adapter = {callback, user_data};
    return rac_llm_llamacpp_generate_stream_with_timing(
        impl, prompt, options, stream_adapter_callback, &adapter, timing_out);
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

// Adaptive context ops
static rac_result_t llamacpp_vtable_inject_system_prompt(void* impl, const char* prompt) {
    return rac_llm_llamacpp_inject_system_prompt(impl, prompt);
}

static rac_result_t llamacpp_vtable_append_context(void* impl, const char* text) {
    return rac_llm_llamacpp_append_context(impl, text);
}

static rac_result_t llamacpp_vtable_generate_from_context(void* impl, const char* query,
                                                          const rac_llm_options_t* options,
                                                          rac_llm_result_t* out_result) {
    return rac_llm_llamacpp_generate_from_context(impl, query, options, out_result);
}

static rac_result_t llamacpp_vtable_clear_context(void* impl) {
    return rac_llm_llamacpp_clear_context(impl);
}

// Static vtable for LlamaCpp
//
// GAP 02 Phase 8: this ops-struct is now also consumed by the unified engine
// plugin entry point in rac_plugin_entry_llamacpp.cpp. The `static` qualifier
// has been dropped so the entry point TU can `extern` it; visibility is still
// limited to the backend library via symbol hiding (the struct is `const`).
// v3 Phase B1: `create` adapter called by commons rac_llm_create() after
// rac_plugin_route picks this plugin. Replaces the legacy factory that was
// registered via rac_service_provider_t::create. The config_json parameter is
// reserved for future engine-specific tuning (num_threads, gpu_layers, etc.);
// today we pass nullptr to rac_llm_llamacpp_create to use defaults.
rac_result_t llamacpp_llm_create_impl(const char* model_id,
                                      const char* /*config_json*/,
                                      void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "llamacpp_llm_create_impl: model=%s", model_id);

    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_id, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_llamacpp_create failed: %d", rc);
        return rc;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

}  // namespace (close anon — ops struct must have external linkage)

// v2 close-out (B3-parallel for llamacpp): g_llamacpp_ops is declared
// `extern const` from rac_plugin_entry_llamacpp.cpp (external linkage). Defining
// it inside the anonymous namespace gave it internal linkage and only worked
// because rac_backend_llamacpp was historically STATIC. The macro now produces
// a SHARED library when RAC_BUILD_SHARED=ON or SHARED_ONLY is set, which
// surfaces the linkage mismatch as undefined-symbol at link time. Wrapping in
// extern "C" makes the definition match the declaration.
extern "C" const rac_llm_service_ops_t g_llamacpp_ops = {
    .initialize = llamacpp_vtable_initialize,
    .generate = llamacpp_vtable_generate,
    .generate_stream = llamacpp_vtable_generate_stream,
    .generate_stream_with_timing = llamacpp_vtable_generate_stream_with_timing,
    .get_info = llamacpp_vtable_get_info,
    .cancel = llamacpp_vtable_cancel,
    .cleanup = llamacpp_vtable_cleanup,
    .destroy = llamacpp_vtable_destroy,
    .load_lora = llamacpp_vtable_load_lora,
    .remove_lora = llamacpp_vtable_remove_lora,
    .clear_lora = llamacpp_vtable_clear_lora,
    .get_lora_info = llamacpp_vtable_get_lora_info,
    .inject_system_prompt = llamacpp_vtable_inject_system_prompt,
    .append_context = llamacpp_vtable_append_context,
    .generate_from_context = llamacpp_vtable_generate_from_context,
    .clear_context = llamacpp_vtable_clear_context,
    .create = llamacpp_llm_create_impl,
};

namespace {  // reopen for the next batch of static helpers

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

// v3 Phase B1: `llamacpp_can_handle` (rac_service_can_handle_fn) and
// `llamacpp_create_service` (rac_service_create_fn) removed. The commons
// consumer (rac_llm_create) now goes through rac_plugin_route → g_llamacpp_ops.create
// which calls llamacpp_llm_create_impl (defined above). Model-format
// gating is handled by the router via g_llamacpp_engine_vtable's
// metadata.formats table in rac_plugin_entry_llamacpp.cpp.

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

    // Module registration stays (independent of the deleted service registry;
    // rac_module_info_t + rac_capability_t are retained in v3 for the module
    // registry which app-level capability discovery still uses).
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

    // v3 Phase B1: plugin registration now happens via the unified
    // rac_plugin_registry (see rac_plugin_entry_llamacpp.cpp). Static
    // builds wire it through RAC_STATIC_PLUGIN_REGISTER (see
    // rac_static_register_llamacpp.cpp); dynamic loads go through
    // plugin_loader.cpp calling rac_plugin_register(rac_plugin_entry_llamacpp()).
    // Backend registration function remains a no-op-ish entry point for
    // callers that import RABackendLlamaCPP and expect a module_register
    // side-effect.
    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Backend registered successfully (module_register only; "
                          "plugin registration via rac_plugin_entry_llamacpp)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // v3: plugin unregistration is the registry's responsibility
    // (rac_plugin_unregister("llamacpp") called by the host). Module
    // registration is the only leftover to tear down here.
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
