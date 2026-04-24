/**
 * @file rac_backend_whispercpp_register.cpp
 * @brief RunAnywhere Core - WhisperCPP Backend RAC Registration
 *
 * Registers the WhisperCPP backend with the module and service registries.
 */

#include "rac_stt_whispercpp.h"

#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char* LOG_CAT = "WhisperCPP";

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0].
 */
static std::vector<float> convert_int16_to_float32(const void* int16_data, size_t byte_count) {
    const int16_t* samples = static_cast<const int16_t*>(int16_data);
    size_t num_samples = byte_count / sizeof(int16_t);

    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
    }

    return float_samples;
}

// Initialize
static rac_result_t whispercpp_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// Transcribe
static rac_result_t whispercpp_stt_vtable_transcribe(void* impl, const void* audio_data,
                                                     size_t audio_size,
                                                     const rac_stt_options_t* options,
                                                     rac_stt_result_t* out_result) {
    if (!audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);
    return rac_stt_whispercpp_transcribe(impl, float_samples.data(), float_samples.size(), options,
                                         out_result);
}

// Get info
static rac_result_t whispercpp_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = rac_stt_whispercpp_is_ready(impl);
    out_info->supports_streaming = RAC_FALSE;  // WhisperCPP streaming is limited
    out_info->current_model = nullptr;

    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t whispercpp_stt_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void whispercpp_stt_vtable_destroy(void* impl) {
    if (impl) {
        rac_stt_whispercpp_destroy(impl);
    }
}

// v3 Phase B4: whispercpp STT `create` adapter. Called by commons
// rac_stt_create() via rac_plugin_route (whisper-ggml priority is
// encoded in g_whispercpp_engine_vtable.metadata.priority in
// rac_plugin_entry_whispercpp.cpp; model-format gating via metadata.formats).
static rac_result_t whispercpp_stt_create_impl(const char* model_id,
                                               const char* /*config_json*/,
                                               void** out_impl) {
    if (!model_id || !out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "whispercpp_stt_create_impl: model=%s", model_id);
    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_stt_whispercpp_create(model_id, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_stt_whispercpp_create failed: %d", rc);
        return rc;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

static rac_result_t whispercpp_stt_vtable_get_languages(void* impl, char** out_json) {
    return rac_stt_whispercpp_get_languages(impl, out_json);
}

static rac_result_t whispercpp_stt_vtable_detect_language(void* impl, const void* audio_data,
                                                          size_t audio_size,
                                                          const rac_stt_options_t* options,
                                                          char** out_language) {
    return rac_stt_whispercpp_detect_language(impl, audio_data, audio_size, options, out_language);
}

const rac_stt_service_ops_t g_whispercpp_stt_ops = {
    .initialize = whispercpp_stt_vtable_initialize,
    .transcribe = whispercpp_stt_vtable_transcribe,
    // Streaming STT not supported by whisper.cpp backend; commons returns
    // RAC_ERROR_NOT_SUPPORTED on NULL. Use sherpa-onnx for live streaming.
    .transcribe_stream = nullptr,
    .get_info = whispercpp_stt_vtable_get_info,
    .cleanup = whispercpp_stt_vtable_cleanup,
    .destroy = whispercpp_stt_vtable_destroy,
    .create = whispercpp_stt_create_impl,
    .get_languages = whispercpp_stt_vtable_get_languages,
    .detect_language = whispercpp_stt_vtable_detect_language,
};

// =============================================================================
// MODULE IDENTITY
// =============================================================================

const char* const MODULE_ID = "whispercpp";

// v3 Phase B4: legacy rac_service_request_t factories removed. Model-file
// gating lives in g_whispercpp_engine_vtable.metadata.formats; backend
// priority (50, lower than ONNX 100) lives in metadata.priority.

bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_whispercpp_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "WhisperCPP";
    module_info.version = "1.0.0";
    module_info.description = "STT backend using whisper.cpp for GGML Whisper models";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 1;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // v3 Phase B4: plugin registration via rac_plugin_entry_whispercpp().
    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "WhisperCPP backend registered (module_register only; "
                          "plugin registration via rac_plugin_entry_whispercpp)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_whispercpp_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
