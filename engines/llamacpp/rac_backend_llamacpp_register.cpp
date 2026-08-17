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
#include <new>
#include <nlohmann/json.hpp>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/plugin/rac_stream_adapter.h"

static const char* LOG_CAT = "LlamaCPP";

// =============================================================================
// VTABLE IMPLEMENTATION - Adapters for generic service interface
// =============================================================================

namespace {

struct LlamaCppRuntimeImpl {
    const rac_runtime_vtable_t* runtime = nullptr;
    rac_runtime_session_t* runtime_session = nullptr;
    rac_handle_t legacy_handle = nullptr;
};

LlamaCppRuntimeImpl* as_runtime_impl(void* impl) {
    return static_cast<LlamaCppRuntimeImpl*>(impl);
}

rac_handle_t legacy_handle(void* impl) {
    auto* runtime_impl = as_runtime_impl(impl);
    return runtime_impl ? runtime_impl->legacy_handle : nullptr;
}

// AcceleratorPolicy wire values (idl/public_api_v4.proto), mirrored the same way
// core/src/core/model_lifecycle.cpp mirrors them rather than pulling the
// generated enum in for three integers.
constexpr int kAcceleratorPolicyCpu = 2;
constexpr int kAcceleratorPolicyGpu = 3;

// Translate commons' advisory load JSON into llama.cpp's own knobs. Returns
// false when there was nothing to say, so the caller can keep passing nullptr
// and leave today's behaviour exactly as it was.
bool parse_load_options(const char* options_json, rac_llm_llamacpp_config_t* config) {
    if (options_json == nullptr || options_json[0] == '\0' || config == nullptr) {
        return false;
    }
    nlohmann::json parsed = nlohmann::json::parse(options_json, nullptr, /*allow_exceptions=*/false);
    if (parsed.is_discarded() || !parsed.is_object()) {
        RAC_LOG_WARNING(LOG_CAT, "ignoring unparseable load options: %s", options_json);
        return false;
    }

    bool any = false;
    if (parsed.contains("context_length") && parsed["context_length"].is_number_integer()) {
        config->context_size = parsed["context_length"].get<int32_t>();
        any = true;
    }
    // accelerator_policy wins over the deprecated use_gpu when both are present,
    // matching the proto comment that calls use_gpu an adapter onto it.
    int policy = 0;
    if (parsed.contains("accelerator_policy") && parsed["accelerator_policy"].is_number_integer()) {
        policy = parsed["accelerator_policy"].get<int>();
    } else if (parsed.contains("use_gpu") && parsed["use_gpu"].is_boolean()) {
        policy = parsed["use_gpu"].get<bool>() ? kAcceleratorPolicyGpu : kAcceleratorPolicyCpu;
    }
    if (policy == kAcceleratorPolicyCpu) {
        config->gpu_layers = 0;  // every layer stays on the CPU
        any = true;
    } else if (policy == kAcceleratorPolicyGpu) {
        config->gpu_layers = -1;  // offload all of them
        any = true;
    }
    // AUTO and NPU are left alone: AUTO is llama.cpp's own fitting pass, and
    // llama.cpp has no NPU path, which commons already warns about separately.
    return any;
}

rac_result_t llamacpp_cpu_provider_create_session(const rac_runtime_session_desc_t* desc,
                                                  rac_runtime_session_t** out) {
    if (desc == nullptr || out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    if (desc->model_path == nullptr || desc->model_path[0] == '\0') {
        return RAC_ERROR_INVALID_PATH;
    }

    // Commons hands the v4 load knobs down as advisory JSON
    // ({"context_length":N,"use_gpu":bool,"accelerator_policy":int}, see
    // model_lifecycle_translation.cpp). Translating them here is what makes
    // `--accelerator cpu|gpu` and `--context-length` actually reach llama.cpp;
    // passing nullptr meant every one of them was dropped on the floor.
    rac_llm_llamacpp_config_t config = RAC_LLM_LLAMACPP_CONFIG_DEFAULT;
    config.gpu_layers = RAC_LLM_LLAMACPP_GPU_LAYERS_AUTO;
    const bool have_config = parse_load_options(desc->options_json, &config);

    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(desc->model_path,
                                              have_config ? &config : nullptr, &backend_handle);
    if (rc != RAC_SUCCESS)
        return rc;
    *out = reinterpret_cast<rac_runtime_session_t*>(backend_handle);
    return RAC_SUCCESS;
}

const rac_runtime_io_t* find_io(const rac_runtime_io_t* ios, size_t count, const char* name) {
    if (ios == nullptr || name == nullptr)
        return nullptr;
    for (size_t i = 0; i < count; ++i) {
        if (ios[i].name != nullptr && std::strcmp(ios[i].name, name) == 0) {
            return &ios[i];
        }
    }
    return nullptr;
}

rac_result_t llamacpp_cpu_provider_run_session(rac_runtime_session_t* session,
                                               const rac_runtime_io_t* inputs, size_t n_in,
                                               rac_runtime_io_t* outputs, size_t n_out) {
    if (session == nullptr)
        return RAC_ERROR_NULL_POINTER;
    const auto* prompt_io = find_io(inputs, n_in, "prompt");
    auto* result_io = const_cast<rac_runtime_io_t*>(find_io(outputs, n_out, "llm_result"));
    if (prompt_io == nullptr || prompt_io->data == nullptr || result_io == nullptr ||
        result_io->data == nullptr || result_io->data_bytes < sizeof(rac_llm_result_t)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const char* prompt = static_cast<const char*>(prompt_io->data);
    const auto* options_io = find_io(inputs, n_in, "llm_options");
    const rac_llm_options_t* options = nullptr;
    if (options_io != nullptr && options_io->data != nullptr &&
        options_io->data_bytes >= sizeof(rac_llm_options_t)) {
        options = static_cast<const rac_llm_options_t*>(options_io->data);
    }

    return rac_llm_llamacpp_generate(reinterpret_cast<rac_handle_t>(session), prompt, options,
                                     static_cast<rac_llm_result_t*>(result_io->data));
}

void llamacpp_cpu_provider_destroy_session(rac_runtime_session_t* session) {
    if (session == nullptr)
        return;
    rac_llm_llamacpp_destroy(reinterpret_cast<rac_handle_t>(session));
}

const uint32_t k_llamacpp_cpu_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_GGML,
    RAC_MODEL_FORMAT_ID_BIN,
};

const rac_cpu_runtime_provider_t k_llamacpp_cpu_provider = {
    /* .name            = */ "llamacpp",
    /* .primitive       = */ RAC_PRIMITIVE_GENERATE_TEXT,
    /* .formats         = */ k_llamacpp_cpu_formats,
    /* .formats_count   = */ sizeof(k_llamacpp_cpu_formats) / sizeof(k_llamacpp_cpu_formats[0]),
    /* .create_session  = */ llamacpp_cpu_provider_create_session,
    /* .run_session     = */ llamacpp_cpu_provider_run_session,
    /* .destroy_session = */ llamacpp_cpu_provider_destroy_session,
};

// Initialize (model already loaded during create for LlamaCpp, so this is a
// no-op)
static rac_result_t llamacpp_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// Generate (blocking)
static rac_result_t llamacpp_vtable_generate(void* impl, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_result_t* out_result) {
    auto* runtime_impl = as_runtime_impl(impl);
    if (runtime_impl == nullptr || runtime_impl->runtime == nullptr ||
        runtime_impl->runtime->run_session == nullptr || runtime_impl->runtime_session == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    rac_runtime_io_t inputs[2] = {};
    size_t n_in = 1;
    inputs[0].name = "prompt";
    inputs[0].data = const_cast<char*>(prompt);
    inputs[0].data_bytes = prompt ? std::strlen(prompt) + 1 : 0;
    if (options != nullptr) {
        inputs[1].name = "llm_options";
        inputs[1].data = const_cast<rac_llm_options_t*>(options);
        inputs[1].data_bytes = sizeof(rac_llm_options_t);
        n_in = 2;
    }
    rac_runtime_io_t output = {};
    output.name = "llm_result";
    output.data = out_result;
    output.data_bytes = sizeof(rac_llm_result_t);
    return runtime_impl->runtime->run_session(runtime_impl->runtime_session, inputs, n_in, &output,
                                              1);
}

// Streaming callback adapter (shared {callback, user_data} bridge; see
// rac/plugin/rac_stream_adapter.h).
using StreamAdapter = rac::plugin::StreamAdapter<rac_llm_stream_callback_fn>;

static rac_bool_t stream_adapter_callback(const char* token, rac_bool_t is_final,
                                          int32_t tokens_in_delta, void* ctx) {
    auto* adapter = static_cast<StreamAdapter*>(ctx);
    // Forward is_final + OpenAI-style finish_reason on the widened commons
    // callback. Keep the side channel as a belt-and-suspenders signal for
    // any commons path that still consults it during migration.
    if (is_final) {
        rac_llm_stream_report_final_signal();
    }
    if (adapter && adapter->callback) {
        const char* reason = is_final ? "stop" : nullptr;
        return adapter->callback(token, is_final, reason, tokens_in_delta, adapter->user_data);
    }
    return RAC_TRUE;
}

// Generate stream
static rac_result_t llamacpp_vtable_generate_stream(void* impl, const char* prompt,
                                                    const rac_llm_options_t* options,
                                                    rac_llm_stream_callback_fn callback,
                                                    void* user_data) {
    StreamAdapter adapter = {callback, user_data};
    return rac_llm_llamacpp_generate_stream(legacy_handle(impl), prompt, options,
                                            stream_adapter_callback, &adapter);
}

// Get info
static rac_result_t llamacpp_vtable_get_info(void* impl, rac_llm_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = rac_llm_llamacpp_is_model_loaded(legacy_handle(impl));
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;  // Default if model not loaded or info unavailable

    // Get actual context_length from model info JSON when model is loaded
    if (out_info->is_ready) {
        char* json_str = nullptr;
        if (rac_llm_llamacpp_get_model_info(legacy_handle(impl), &json_str) == RAC_SUCCESS &&
            json_str) {
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
    rac_llm_llamacpp_cancel(legacy_handle(impl));
    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t llamacpp_vtable_cleanup(void* impl) {
    return rac_llm_llamacpp_unload_model(legacy_handle(impl));
}

// Destroy
static void llamacpp_vtable_destroy(void* impl) {
    auto* runtime_impl = as_runtime_impl(impl);
    if (runtime_impl == nullptr)
        return;
    if (runtime_impl->runtime && runtime_impl->runtime->destroy_session) {
        runtime_impl->runtime->destroy_session(runtime_impl->runtime_session);
    }
    delete runtime_impl;
}

// LoRA adapter management
static rac_result_t llamacpp_vtable_load_lora(void* impl, const char* adapter_path, float scale) {
    return rac_llm_llamacpp_load_lora(legacy_handle(impl), adapter_path, scale);
}

static rac_result_t llamacpp_vtable_remove_lora(void* impl, const char* adapter_path) {
    return rac_llm_llamacpp_remove_lora(legacy_handle(impl), adapter_path);
}

static rac_result_t llamacpp_vtable_clear_lora(void* impl) {
    return rac_llm_llamacpp_clear_lora(legacy_handle(impl));
}

static rac_result_t llamacpp_vtable_get_lora_info(void* impl, char** out_json) {
    return rac_llm_llamacpp_get_lora_info(legacy_handle(impl), out_json);
}

// Adaptive context ops
static rac_result_t llamacpp_vtable_inject_system_prompt(void* impl, const char* prompt) {
    return rac_llm_llamacpp_inject_system_prompt(legacy_handle(impl), prompt);
}

static rac_result_t llamacpp_vtable_append_context(void* impl, const char* text) {
    return rac_llm_llamacpp_append_context(legacy_handle(impl), text);
}

static rac_result_t llamacpp_vtable_generate_from_context(void* impl, const char* query,
                                                          const rac_llm_options_t* options,
                                                          rac_llm_result_t* out_result) {
    return rac_llm_llamacpp_generate_from_context(legacy_handle(impl), query, options, out_result);
}

static rac_result_t llamacpp_vtable_clear_context(void* impl) {
    return rac_llm_llamacpp_clear_context(legacy_handle(impl));
}

static rac_result_t llamacpp_vtable_get_stream_token_counts(void* impl,
                                                            rac_llm_token_counts_t* out) {
    return rac_llm_llamacpp_get_stream_token_counts(legacy_handle(impl), out);
}

// Static vtable for LlamaCpp
//
// This ops-struct is now also consumed by the unified engine
// plugin entry point in rac_plugin_entry_llamacpp.cpp. The `static` qualifier
// has been dropped so the entry point TU can `extern` it; visibility is still
// limited to the backend library via symbol hiding (the struct is `const`).
// The `create` adapter called by commons rac_llm_create() after
// rac_plugin_find picks this plugin. Replaces the legacy factory that was
// registered via rac_service_provider_t::create. config_json carries commons'
// advisory load knobs and rides on the session descriptor to the provider,
// which translates it into rac_llm_llamacpp_config_t.
rac_result_t llamacpp_llm_create_impl(const char* model_id, const char* config_json,
                                      void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "llamacpp_llm_create_impl: model=%s", model_id);

    const rac_runtime_vtable_t* runtime = rac_runtime_get_by_id(RAC_RUNTIME_CPU);
    rac_result_t rc = runtime ? RAC_SUCCESS : RAC_ERROR_NOT_FOUND;
    if (rc != RAC_SUCCESS || runtime == nullptr || runtime->create_session == nullptr ||
        runtime->run_session == nullptr || runtime->destroy_session == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "CPU runtime session ops unavailable: %d", rc);
        return rc == RAC_SUCCESS ? RAC_ERROR_NOT_IMPLEMENTED : rc;
    }

    rac_runtime_session_desc_t desc = {};
    desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    desc.model_format = RAC_MODEL_FORMAT_ID_GGUF;
    desc.model_path = model_id;
    // The CPU runtime forwards the descriptor untouched, so this is how the
    // load knobs reach llamacpp_cpu_provider_create_session.
    desc.options_json = config_json;

    rac_runtime_session_t* runtime_session = nullptr;
    rc = runtime->create_session(&desc, &runtime_session);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "CPU runtime create_session failed: %d", rc);
        return rc;
    }

    rac_runtime_session_t* provider_session = nullptr;
    rc = rac_cpu_runtime_get_provider_session(runtime_session, nullptr, &provider_session);
    if (rc != RAC_SUCCESS || provider_session == nullptr) {
        runtime->destroy_session(runtime_session);
        return rc == RAC_SUCCESS ? RAC_ERROR_INVALID_HANDLE : rc;
    }

    auto* runtime_impl = new (std::nothrow) LlamaCppRuntimeImpl();
    if (runtime_impl == nullptr) {
        runtime->destroy_session(runtime_session);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    runtime_impl->runtime = runtime;
    runtime_impl->runtime_session = runtime_session;
    runtime_impl->legacy_handle = reinterpret_cast<rac_handle_t>(provider_session);
    *out_impl = runtime_impl;
    return RAC_SUCCESS;
}

}  // namespace

// g_llamacpp_ops is declared
// `extern const` from rac_plugin_entry_llamacpp.cpp (external linkage).
// Defining it inside the anonymous namespace gave it internal linkage and only
// worked because rac_backend_llamacpp was historically STATIC. The macro now
// produces a SHARED library when RAC_BUILD_SHARED=ON or SHARED_ONLY is set,
// which surfaces the linkage mismatch as undefined-symbol at link time.
// Wrapping in extern "C" makes the definition match the declaration.
// RAC_LLAMACPP_API exports it from rac_backend_llamacpp.dll on Windows so the
// thin runanywhere_llamacpp carrier can dllimport it.
extern "C" RAC_LLAMACPP_API const rac_llm_service_ops_t g_llamacpp_ops = {
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
    .inject_system_prompt = llamacpp_vtable_inject_system_prompt,
    .append_context = llamacpp_vtable_append_context,
    .generate_from_context = llamacpp_vtable_generate_from_context,
    .clear_context = llamacpp_vtable_clear_context,
    .create = llamacpp_llm_create_impl,
    .get_stream_token_counts = llamacpp_vtable_get_stream_token_counts,
};

namespace {  // reopen for the next batch of static helpers

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct LlamaCPPRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_name[32] = "LlamaCPPService";
};

LlamaCPPRegistryState& get_state() {
    static LlamaCPPRegistryState state;
    return state;
}

// `llamacpp_can_handle` (rac_service_can_handle_fn) and
// `llamacpp_create_service` (rac_service_create_fn) removed. The commons
// consumer (rac_llm_create) now goes through rac_plugin_find →
// g_llamacpp_ops.create which calls llamacpp_llm_create_impl (defined above).
// g_llamacpp_engine_vtable's metadata.formats table (in
// rac_plugin_entry_llamacpp.cpp) is advisory metadata, not used for selection.

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

RAC_LLAMACPP_API rac_result_t rac_llamacpp_cpu_runtime_register(void) {
    return rac_cpu_runtime_register_provider(&k_llamacpp_cpu_provider);
}

RAC_LLAMACPP_API void rac_llamacpp_cpu_runtime_unregister(void) {
    rac_cpu_runtime_unregister_provider(k_llamacpp_cpu_provider.name);
}

rac_result_t rac_backend_llamacpp_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Android-fix: on dynamic-plugin hosts the static-register shim's ctor only
    // fires if the carrier `librunanywhere_llamacpp.so` is dlopened — which
    // Kotlin/JNI does not do (it loads `librac_backend_llamacpp_jni.so`, which
    // links the backend directly). Register the plugin entry here so
    // rac_plugin_find can find the unified vtable (with
    // both llm_ops and vlm_ops slots filled). Mirrors the pattern in
    // rac_backend_onnx_register.cpp.
    // The unified llamacpp plugin already serves both LLM and VLM primitives
    // and registers only under "llamacpp"; there is no alias normalization, so
    // the legacy "llamacpp_vlm" plugin entry no longer exists and is not
    // registered here.
    const rac_engine_vtable_t* vt = rac_plugin_entry_llamacpp();
    if (vt != nullptr) {
        rac_result_t plugin_rc = rac_plugin_register(vt);
        if (plugin_rc != RAC_SUCCESS && plugin_rc != RAC_ERROR_PLUGIN_DUPLICATE) {
            RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register failed: %d", plugin_rc);
        } else {
            RAC_LOG_INFO(LOG_CAT, "rac_plugin_register succeeded for 'llamacpp'");
        }
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Backend registered successfully (module + plugin)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_llamacpp_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // Plugin unregistration is the registry's responsibility
    // (rac_plugin_unregister("llamacpp") called by the host).
    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
