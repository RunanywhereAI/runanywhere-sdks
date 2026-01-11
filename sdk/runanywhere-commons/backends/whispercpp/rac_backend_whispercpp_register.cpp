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
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);
    return rac_stt_whispercpp_transcribe(impl, float_samples.data(), float_samples.size(), options,
                                         out_result);
}

// Stream transcription (not implemented for WhisperCPP - use batch)
static rac_result_t whispercpp_stt_vtable_transcribe_stream(void* impl, const void* audio_data,
                                                            size_t audio_size,
                                                            const rac_stt_options_t* options,
                                                            rac_stt_stream_callback_t callback,
                                                            void* user_data) {
    // Fall back to batch transcription
    rac_stt_result_t result = {};
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);
    rac_result_t status =
        rac_stt_whispercpp_transcribe(impl, float_samples.data(), float_samples.size(), options,
                                      &result);
    if (status == RAC_SUCCESS && callback && result.text) {
        callback(result.text, RAC_TRUE, user_data);
    }
    return status;
}

// Get info
static rac_result_t whispercpp_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;

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

// Static vtable for WhisperCPP STT
static const rac_stt_service_ops_t g_whispercpp_stt_ops = {
    .initialize = whispercpp_stt_vtable_initialize,
    .transcribe = whispercpp_stt_vtable_transcribe,
    .transcribe_stream = whispercpp_stt_vtable_transcribe_stream,
    .get_info = whispercpp_stt_vtable_get_info,
    .cleanup = whispercpp_stt_vtable_cleanup,
    .destroy = whispercpp_stt_vtable_destroy,
};

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

const char* const MODULE_ID = "whispercpp";
const char* const STT_PROVIDER_NAME = "WhisperCPPSTTService";

// STT can_handle
rac_bool_t whispercpp_stt_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Don't be the default STT provider (let ONNX handle that)
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_FALSE;
    }

    // Check for whisper GGML model patterns
    const char* path = request->identifier;
    size_t len = strlen(path);

    // Check for .bin extension (whisper GGML format)
    if (len >= 4) {
        const char* ext = path + len - 4;
        if (strcmp(ext, ".bin") == 0 || strcmp(ext, ".BIN") == 0) {
            if (strstr(path, "whisper") != nullptr || strstr(path, "ggml") != nullptr) {
                RAC_LOG_INFO(LOG_CAT, "whispercpp_stt_can_handle: path matches -> TRUE");
                return RAC_TRUE;
            }
        }
    }

    return RAC_FALSE;
}

// STT create with vtable
rac_handle_t whispercpp_stt_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating WhisperCPP STT service for: %s",
                 request->identifier ? request->identifier : "(default)");

    rac_handle_t backend_handle = nullptr;
    rac_result_t result = rac_stt_whispercpp_create(request->identifier, nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_stt_whispercpp_create failed with result: %d", result);
        return nullptr;
    }

    auto* service = static_cast<rac_stt_service_t*>(malloc(sizeof(rac_stt_service_t)));
    if (!service) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate rac_stt_service_t");
        rac_stt_whispercpp_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_whispercpp_stt_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "WhisperCPP STT service created successfully");
    return service;
}

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

    // Register module
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

    // Register STT provider with lower priority than ONNX
    // (to avoid GGML symbol conflicts when LlamaCPP is also loaded)
    rac_service_provider_t stt_provider = {};
    stt_provider.name = STT_PROVIDER_NAME;
    stt_provider.capability = RAC_CAPABILITY_STT;
    stt_provider.priority = 50;  // Lower than ONNX (100)
    stt_provider.can_handle = whispercpp_stt_can_handle;
    stt_provider.create = whispercpp_stt_create;

    result = rac_service_register_provider(&stt_provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "WhisperCPP backend registered (STT)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_whispercpp_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"

