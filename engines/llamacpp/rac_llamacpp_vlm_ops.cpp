/**
 * @file rac_llamacpp_vlm_ops.cpp
 * @brief VLM ops vtable for llama.cpp — extracted from the (now-deleted)
 *        rac_backend_llamacpp_vlm_register.cpp.
 *
 * After the LLM/VLM plugin unification, llama.cpp publishes a SINGLE plugin
 * vtable (in `rac_plugin_entry_llamacpp.cpp`) that fills both the `llm_ops`
 * and `vlm_ops` slots. This TU owns the `g_llamacpp_vlm_ops` struct definition
 * and the adapter functions wiring the generic VLM service vtable to the
 * underlying `rac_vlm_llamacpp_*` C API. The separate "llamacpp_vlm" plugin
 * name / module / register function are gone — there is only one
 * `rac_backend_llamacpp_register()` that announces both capabilities.
 */

#include <cstdlib>
#include <nlohmann/json.hpp>
#include <string>

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/backends/rac_vlm_llamacpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_stream_adapter.h"

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

// Streaming callback adapter (shared {callback, user_data} bridge; see
// rac/plugin/rac_stream_adapter.h).
using VLMStreamAdapter = rac::plugin::StreamAdapter<rac_vlm_stream_callback_fn>;

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

    // Get actual info from model. nlohmann::json is already linked.
    if (out_info->is_ready) {
        char* json_str = nullptr;
        if (rac_vlm_llamacpp_get_model_info(impl, &json_str) == RAC_SUCCESS && json_str) {
            try {
                auto json = nlohmann::json::parse(json_str);
                out_info->context_length =
                    static_cast<int32_t>(json.at("context_size").get<int64_t>());
            } catch (...) {
                // JSON parse / key-missing / type mismatch → leave context_length = 0.
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

// AcceleratorPolicy wire values, mirrored from idl/model_types.proto for the
// same reason rac_backend_llamacpp_register.cpp mirrors them: they arrive as
// JSON numbers over the config_json ABI and this engine links neither protobuf
// nor the generated tree. Keep in step with ACCELERATOR_POLICY_CPU/GPU.
constexpr int kAcceleratorPolicyCpu = 2;  // ACCELERATOR_POLICY_CPU
constexpr int kAcceleratorPolicyGpu = 3;  // ACCELERATOR_POLICY_GPU

// `create` adapter for llama.cpp VLM. Parses "mmproj_path" (so VLM's 2-path
// create signature maps cleanly into the uniform rac_vlm_service_ops_t::create
// slot) plus the same load knobs the LLM path honours.
rac_result_t llamacpp_vlm_create_impl(const char* model_id, const char* config_json,
                                      void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;

    std::string mmproj_path_owned;
    const char* mmproj_path = nullptr;
    rac_vlm_llamacpp_config_t config = RAC_VLM_LLAMACPP_CONFIG_DEFAULT;
    // Stays false when config_json said nothing about placement or context, so
    // the create call below keeps passing nullptr and behaviour is unchanged.
    bool have_config = false;
    if (config_json && config_json[0] != '\0') {
        try {
            auto json = nlohmann::json::parse(config_json);
            if (json.contains("mmproj_path") && json["mmproj_path"].is_string()) {
                mmproj_path_owned = json["mmproj_path"].get<std::string>();
                mmproj_path = mmproj_path_owned.c_str();
                RAC_LOG_DEBUG(LOG_CAT, "Parsed mmproj_path from config_json: %s", mmproj_path);
            }
            if (json.contains("context_length") && json["context_length"].is_number_integer()) {
                config.context_size = json["context_length"].get<int32_t>();
                have_config = true;
            }
            // accelerator_policy wins over the deprecated use_gpu when both are
            // present, matching the proto comment that calls use_gpu an adapter
            // onto it.
            int policy = 0;
            if (json.contains("accelerator_policy") &&
                json["accelerator_policy"].is_number_integer()) {
                policy = json["accelerator_policy"].get<int>();
            } else if (json.contains("use_gpu") && json["use_gpu"].is_boolean()) {
                policy = json["use_gpu"].get<bool>() ? kAcceleratorPolicyGpu
                                                     : kAcceleratorPolicyCpu;
            }
            if (policy == kAcceleratorPolicyCpu) {
                config.gpu_layers = 0;       // every layer stays on the CPU
                config.use_gpu_vision = 0;   // and so does the vision encoder
                have_config = true;
            } else if (policy == kAcceleratorPolicyGpu) {
                config.gpu_layers = -1;  // offload all of them
                have_config = true;
            }
            // AUTO and NPU are left alone for the same reasons as the LLM path.
        } catch (const std::exception& e) {
            RAC_LOG_WARNING(LOG_CAT, "config_json parse failed (%s); using defaults", e.what());
        }
    }

    RAC_LOG_INFO(LOG_CAT, "llamacpp_vlm_create_impl: model=%s, mmproj=%s", model_id,
                 mmproj_path ? mmproj_path : "(none)");

    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_vlm_llamacpp_create(model_id, mmproj_path,
                                              have_config ? &config : nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_vlm_llamacpp_create failed: %d", rc);
        return rc;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

}  // namespace

// Exposed with external linkage so rac_plugin_entry_llamacpp.cpp can extern-
// reference it when filling the unified engine vtable's `vlm_ops` slot.
// RAC_LLAMACPP_API: export from rac_backend_llamacpp.dll for Windows thin carriers.
extern "C" RAC_LLAMACPP_API const rac_vlm_service_ops_t g_llamacpp_vlm_ops = {
    .initialize = llamacpp_vlm_vtable_initialize,
    .process = llamacpp_vlm_vtable_process,
    .process_stream = llamacpp_vlm_vtable_process_stream,
    .get_info = llamacpp_vlm_vtable_get_info,
    .cancel = llamacpp_vlm_vtable_cancel,
    .cleanup = llamacpp_vlm_vtable_cleanup,
    .destroy = llamacpp_vlm_vtable_destroy,
    .create = llamacpp_vlm_create_impl,
};
