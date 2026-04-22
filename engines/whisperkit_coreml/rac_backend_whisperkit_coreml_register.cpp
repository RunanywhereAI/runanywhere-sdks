/**
 * @file rac_backend_whisperkit_coreml_register.cpp
 * @brief RunAnywhere Commons - WhisperKit CoreML Backend Registration
 *
 * Registers the WhisperKit CoreML backend with the module and service registries.
 * Provides an STT vtable that delegates to Swift via callbacks for CoreML
 * inference on Apple Neural Engine.
 */

#include <cstdlib>
#include <cstring>

#include "rac/backends/rac_stt_whisperkit_coreml.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char* LOG_CAT = "WhisperKitCoreML";

static rac_result_t whisperkit_coreml_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

static rac_result_t whisperkit_coreml_stt_vtable_transcribe(void* impl, const void* audio_data,
                                                            size_t audio_size,
                                                            const rac_stt_options_t* options,
                                                            rac_stt_result_t* out_result) {
    if (!impl || !audio_data || !out_result)
        return RAC_ERROR_NULL_POINTER;

    const auto* callbacks = rac_whisperkit_coreml_stt_get_callbacks();
    if (!callbacks || !callbacks->transcribe) {
        RAC_LOG_ERROR(LOG_CAT, "Swift transcribe callback not registered");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return callbacks->transcribe(impl, audio_data, audio_size, options, out_result,
                                 callbacks->user_data);
}

static rac_result_t whisperkit_coreml_stt_vtable_transcribe_stream(
    void* impl, const void* audio_data, size_t audio_size, const rac_stt_options_t* options,
    rac_stt_stream_callback_t callback, void* user_data) {
    rac_stt_result_t result = {};
    rac_result_t status =
        whisperkit_coreml_stt_vtable_transcribe(impl, audio_data, audio_size, options, &result);
    if (status == RAC_SUCCESS && callback && result.text) {
        callback(result.text, RAC_TRUE, user_data);
    }
    rac_stt_result_free(&result);
    return status;
}

static rac_result_t whisperkit_coreml_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    (void)impl;
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = (impl != nullptr) ? RAC_TRUE : RAC_FALSE;
    out_info->supports_streaming = RAC_FALSE;
    out_info->current_model = nullptr;

    return RAC_SUCCESS;
}

static rac_result_t whisperkit_coreml_stt_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

static void whisperkit_coreml_stt_vtable_destroy(void* impl) {
    if (!impl)
        return;

    const auto* callbacks = rac_whisperkit_coreml_stt_get_callbacks();
    if (callbacks && callbacks->destroy) {
        callbacks->destroy(impl, callbacks->user_data);
    }
}

// v3 Phase B5: WhisperKit CoreML `create` adapter. Delegates to the
// Swift-side create callback (whisperkit_coreml is driven via Swift
// callbacks registered through rac_whisperkit_coreml_stt_get_callbacks).
// Called by commons rac_stt_create() via rac_plugin_route on Apple
// platforms where WhisperKit CoreML is available. For `create`, we use
// model_id as both the model path and the model id — the legacy factory
// used request->model_path ?: request->identifier, both of which mapped
// to the same value in the consumer path.
static rac_result_t whisperkit_coreml_stt_create_impl(const char* model_id,
                                                      const char* /*config_json*/,
                                                      void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;

    const auto* callbacks = rac_whisperkit_coreml_stt_get_callbacks();
    if (!callbacks || !callbacks->create) {
        RAC_LOG_ERROR(LOG_CAT, "create: Swift callbacks not registered");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO(LOG_CAT,
                 "whisperkit_coreml_stt_create_impl: model=%s",
                 model_id ? model_id : "(default)");

    rac_handle_t backend_handle =
        callbacks->create(model_id, model_id, callbacks->user_data);
    if (!backend_handle) {
        RAC_LOG_ERROR(LOG_CAT, "Swift create callback returned null");
        return RAC_ERROR_UNKNOWN;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

const rac_stt_service_ops_t g_whisperkit_coreml_stt_ops = {
    .initialize = whisperkit_coreml_stt_vtable_initialize,
    .transcribe = whisperkit_coreml_stt_vtable_transcribe,
    .transcribe_stream = whisperkit_coreml_stt_vtable_transcribe_stream,
    .get_info = whisperkit_coreml_stt_vtable_get_info,
    .cleanup = whisperkit_coreml_stt_vtable_cleanup,
    .destroy = whisperkit_coreml_stt_vtable_destroy,
    .create = whisperkit_coreml_stt_create_impl,
};

// =============================================================================
// MODULE IDENTITY
// =============================================================================

const char* const MODULE_ID = "whisperkit_coreml";

// v3: legacy rac_service_request_t factories removed. Framework gating
// (RAC_FRAMEWORK_WHISPERKIT_COREML) + availability check is now in
// g_whisperkit_coreml_engine_vtable.metadata in the plugin-entry TU.

bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_whisperkit_coreml_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "WhisperKit CoreML";
    module_info.version = "1.0.0";
    module_info.description = "STT backend using WhisperKit CoreML (Apple Neural Engine)";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // v3 Phase B5: plugin registration via rac_plugin_entry_whisperkit_coreml().
    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "WhisperKit CoreML backend registered (module_register only; "
                          "plugin registration via rac_plugin_entry_whisperkit_coreml)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_whisperkit_coreml_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_module_unregister(MODULE_ID);

    g_registered = false;
    RAC_LOG_INFO(LOG_CAT, "WhisperKit CoreML backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
