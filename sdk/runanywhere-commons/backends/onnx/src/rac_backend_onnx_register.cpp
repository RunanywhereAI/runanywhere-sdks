/**
 * @file rac_backend_onnx_register.cpp
 * @brief RunAnywhere Commons - ONNX Backend Registration
 *
 * Registers the ONNX backend with the module and service registries.
 * Provides vtable implementations for STT, TTS, and VAD services.
 */

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// Forward declaration for runanywhere-core ONNX backend registration
// This registers the ONNX backend in runanywhere-core's BackendRegistry
// so that ra_create_backend("onnx") can work
namespace runanywhere {
    void register_onnx_backend();
}

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char* LOG_CAT = "ONNX";

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0].
 * Swift sends Int16 audio but Sherpa-ONNX expects Float32.
 */
static std::vector<float> convert_int16_to_float32(const void* int16_data, size_t byte_count) {
    const int16_t* samples = static_cast<const int16_t*>(int16_data);
    size_t num_samples = byte_count / sizeof(int16_t);

    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        // Normalize Int16 [-32768, 32767] to Float32 [-1.0, 1.0]
        float_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
    }

    return float_samples;
}

// Initialize (no-op for ONNX - model loaded during create)
static rac_result_t onnx_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// Transcribe - converts Int16 PCM to Float32 for Sherpa-ONNX
static rac_result_t onnx_stt_vtable_transcribe(void* impl, const void* audio_data,
                                               size_t audio_size, const rac_stt_options_t* options,
                                               rac_stt_result_t* out_result) {
    // Convert Int16 PCM to Float32 (Swift sends Int16, Sherpa-ONNX expects Float32)
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);
    return rac_stt_onnx_transcribe(impl, float_samples.data(), float_samples.size(), options,
                                   out_result);
}

// Stream transcription - uses ONNX streaming API
static rac_result_t onnx_stt_vtable_transcribe_stream(void* impl, const void* audio_data,
                                                      size_t audio_size,
                                                      const rac_stt_options_t* options,
                                                      rac_stt_stream_callback_t callback,
                                                      void* user_data) {
    (void)options;

    // Create stream handle
    rac_handle_t stream = nullptr;
    rac_result_t result = rac_stt_onnx_create_stream(impl, &stream);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // Convert Int16 PCM to Float32
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);

    // Feed audio to stream
    result = rac_stt_onnx_feed_audio(impl, stream, float_samples.data(), float_samples.size());
    if (result != RAC_SUCCESS) {
        rac_stt_onnx_destroy_stream(impl, stream);
        return result;
    }

    // Signal end of input
    rac_stt_onnx_input_finished(impl, stream);

    // Decode and callback
    char* text = nullptr;
    result = rac_stt_onnx_decode_stream(impl, stream, &text);
    if (result == RAC_SUCCESS && callback && text) {
        callback(text, RAC_TRUE, user_data);
    }

    // Cleanup
    rac_stt_onnx_destroy_stream(impl, stream);
    if (text)
        free(text);

    return result;
}

// Get info
static rac_result_t onnx_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = rac_stt_onnx_supports_streaming(impl);
    out_info->current_model = nullptr;

    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t onnx_stt_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void onnx_stt_vtable_destroy(void* impl) {
    if (impl) {
        rac_stt_onnx_destroy(impl);
    }
}

// Static vtable for ONNX STT
static const rac_stt_service_ops_t g_onnx_stt_ops = {
    .initialize = onnx_stt_vtable_initialize,
    .transcribe = onnx_stt_vtable_transcribe,
    .transcribe_stream = onnx_stt_vtable_transcribe_stream,
    .get_info = onnx_stt_vtable_get_info,
    .cleanup = onnx_stt_vtable_cleanup,
    .destroy = onnx_stt_vtable_destroy,
};

// =============================================================================
// TTS VTABLE IMPLEMENTATION
// =============================================================================

// Initialize (no-op)
static rac_result_t onnx_tts_vtable_initialize(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Synthesize
static rac_result_t onnx_tts_vtable_synthesize(void* impl, const char* text,
                                               const rac_tts_options_t* options,
                                               rac_tts_result_t* out_result) {
    return rac_tts_onnx_synthesize(impl, text, options, out_result);
}

// Stream synthesis (not implemented for ONNX)
static rac_result_t onnx_tts_vtable_synthesize_stream(void* impl, const char* text,
                                                      const rac_tts_options_t* options,
                                                      rac_tts_stream_callback_t callback,
                                                      void* user_data) {
    // Fall back to batch synthesis
    rac_tts_result_t result = {};
    rac_result_t status = rac_tts_onnx_synthesize(impl, text, options, &result);
    if (status == RAC_SUCCESS && callback) {
        callback(result.audio_data, result.audio_size, user_data);
    }
    return status;
}

// Stop
static rac_result_t onnx_tts_vtable_stop(void* impl) {
    rac_tts_onnx_stop(impl);
    return RAC_SUCCESS;
}

// Get info
static rac_result_t onnx_tts_vtable_get_info(void* impl, rac_tts_info_t* out_info) {
    (void)impl;
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;

    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t onnx_tts_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void onnx_tts_vtable_destroy(void* impl) {
    if (impl) {
        rac_tts_onnx_destroy(impl);
    }
}

// Static vtable for ONNX TTS
static const rac_tts_service_ops_t g_onnx_tts_ops = {
    .initialize = onnx_tts_vtable_initialize,
    .synthesize = onnx_tts_vtable_synthesize,
    .synthesize_stream = onnx_tts_vtable_synthesize_stream,
    .stop = onnx_tts_vtable_stop,
    .get_info = onnx_tts_vtable_get_info,
    .cleanup = onnx_tts_vtable_cleanup,
    .destroy = onnx_tts_vtable_destroy,
};

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

const char* const MODULE_ID = "onnx";
const char* const STT_PROVIDER_NAME = "ONNXSTTService";
const char* const TTS_PROVIDER_NAME = "ONNXTTSService";
const char* const VAD_PROVIDER_NAME = "ONNXVADService";

// STT can_handle
rac_bool_t onnx_stt_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle called");

    if (request == nullptr) {
        RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle: request is null -> FALSE");
        return RAC_FALSE;
    }

    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle: no identifier -> TRUE (default)");
        return RAC_TRUE;  // Default provider
    }

    const char* path = request->identifier;
    RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle: checking path=%s", path);

    if (strstr(path, "whisper") != nullptr || strstr(path, "zipformer") != nullptr ||
        strstr(path, "paraformer") != nullptr || strstr(path, ".onnx") != nullptr) {
        RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle: path matches -> TRUE");
        return RAC_TRUE;
    }

    RAC_LOG_INFO(LOG_CAT, "onnx_stt_can_handle: path doesn't match -> FALSE");
    return RAC_FALSE;
}

// STT create with vtable
rac_handle_t onnx_stt_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    RAC_LOG_INFO(LOG_CAT, "onnx_stt_create ENTRY - provider create callback invoked");

    if (request == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "onnx_stt_create: request is null");
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating ONNX STT service for: %s",
                 request->identifier ? request->identifier : "(default)");

    // Create backend handle
    rac_handle_t backend_handle = nullptr;
    RAC_LOG_INFO(LOG_CAT, "Calling rac_stt_onnx_create...");
    rac_result_t result = rac_stt_onnx_create(request->identifier, nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_stt_onnx_create failed with result: %d", result);
        return nullptr;
    }
    RAC_LOG_INFO(LOG_CAT, "rac_stt_onnx_create succeeded, backend_handle=%p", backend_handle);

    // Allocate service with vtable
    auto* service = static_cast<rac_stt_service_t*>(malloc(sizeof(rac_stt_service_t)));
    if (!service) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate rac_stt_service_t");
        rac_stt_onnx_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_onnx_stt_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "ONNX STT service created successfully, service=%p", service);
    return service;
}

// TTS can_handle
rac_bool_t onnx_tts_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;  // Default provider
    }

    const char* path = request->identifier;
    if (strstr(path, "piper") != nullptr || strstr(path, "vits") != nullptr ||
        strstr(path, ".onnx") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

// TTS create with vtable
rac_handle_t onnx_tts_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating ONNX TTS service for: %s",
                 request->identifier ? request->identifier : "(default)");

    // Create backend handle
    rac_handle_t backend_handle = nullptr;
    rac_result_t result = rac_tts_onnx_create(request->identifier, nullptr, &backend_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create ONNX TTS backend: %d", result);
        return nullptr;
    }

    // Allocate service with vtable
    auto* service = static_cast<rac_tts_service_t*>(malloc(sizeof(rac_tts_service_t)));
    if (!service) {
        rac_tts_onnx_destroy(backend_handle);
        return nullptr;
    }

    service->ops = &g_onnx_tts_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "ONNX TTS service created successfully");
    return service;
}

// VAD can_handle
rac_bool_t onnx_vad_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;
    (void)request;
    return RAC_TRUE;  // ONNX handles all VAD
}

// VAD create (no vtable needed - VAD uses different pattern)
rac_handle_t onnx_vad_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    const char* model_path = nullptr;
    if (request != nullptr) {
        model_path = request->identifier;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_vad_onnx_create(model_path, nullptr, &handle);
    return (result == RAC_SUCCESS) ? handle : nullptr;
}

// =============================================================================
// STORAGE AND DOWNLOAD STRATEGIES
// =============================================================================

const char* STRATEGY_LOG_CAT = "ONNXStrategy";

rac_result_t onnx_storage_find_model_path(const char* model_id, const char* model_folder,
                                          char* out_path, size_t path_size, void* user_data) {
    (void)user_data;

    if (!model_id || !model_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    int written = snprintf(out_path, path_size, "%s/%s.onnx", model_folder, model_id);
    if (written < 0 || (size_t)written >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    return RAC_SUCCESS;
}

rac_result_t onnx_storage_detect_model(const char* model_folder,
                                       rac_model_storage_details_t* out_details, void* user_data) {
    (void)user_data;

    if (!model_folder || !out_details) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    memset(out_details, 0, sizeof(rac_model_storage_details_t));
    out_details->format = RAC_MODEL_FORMAT_ONNX;
    out_details->is_directory_based = RAC_TRUE;
    out_details->is_valid = RAC_TRUE;
    out_details->total_size = 0;
    out_details->file_count = 1;
    out_details->primary_file = nullptr;

    return RAC_SUCCESS;
}

rac_bool_t onnx_storage_is_valid(const char* model_folder, void* user_data) {
    (void)user_data;
    return model_folder ? RAC_TRUE : RAC_FALSE;
}

void onnx_storage_get_patterns(const char*** out_patterns, size_t* out_count, void* user_data) {
    (void)user_data;

    static const char* patterns[] = {"*.onnx", "*.ort", "encoder*.onnx", "decoder*.onnx",
                                     "model.onnx"};
    *out_patterns = patterns;
    *out_count = sizeof(patterns) / sizeof(patterns[0]);
}

rac_result_t onnx_download_prepare(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;
    return (config && config->model_id && config->destination_folder) ? RAC_SUCCESS
                                                                      : RAC_ERROR_INVALID_PARAMETER;
}

rac_result_t onnx_download_get_dest(const rac_model_download_config_t* config, char* out_path,
                                    size_t path_size, void* user_data) {
    (void)user_data;

    if (!config || !config->destination_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    int written =
        snprintf(out_path, path_size, "%s/%s", config->destination_folder, config->model_id);
    return (written < 0 || (size_t)written >= path_size) ? RAC_ERROR_BUFFER_TOO_SMALL : RAC_SUCCESS;
}

rac_result_t onnx_download_post_process(const rac_model_download_config_t* config,
                                        const char* downloaded_path,
                                        rac_download_result_t* out_result, void* user_data) {
    (void)user_data;

    if (!config || !downloaded_path || !out_result) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    memset(out_result, 0, sizeof(rac_download_result_t));
    out_result->was_extracted =
        (config->archive_type != RAC_ARCHIVE_TYPE_NONE) ? RAC_TRUE : RAC_FALSE;
    out_result->final_path = strdup(downloaded_path);
    out_result->file_count = 1;

    return RAC_SUCCESS;
}

void onnx_download_cleanup(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;
    (void)config;
}

static rac_storage_strategy_t g_onnx_storage_strategy = {onnx_storage_find_model_path,
                                                         onnx_storage_detect_model,
                                                         onnx_storage_is_valid,
                                                         onnx_storage_get_patterns,
                                                         nullptr,
                                                         "ONNXStorageStrategy"};

static rac_download_strategy_t g_onnx_download_strategy = {onnx_download_prepare,
                                                           onnx_download_get_dest,
                                                           onnx_download_post_process,
                                                           onnx_download_cleanup,
                                                           nullptr,
                                                           "ONNXDownloadStrategy"};

bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_onnx_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register ONNX backend in runanywhere-core's BackendRegistry
    // This must be called before ra_create_backend("onnx") can work
    // NOTE: ensure_backends_registered() in runanywhere_bridge.cpp also registers
    // backends, but we call this explicitly to ensure it happens early
    try {
        runanywhere::register_onnx_backend();
        RAC_LOG_INFO(LOG_CAT, "ONNX backend registered in runanywhere-core BackendRegistry");
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to register ONNX backend in core: %s", e.what());
        // Continue anyway - ensure_backends_registered() might handle it
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "ONNX Runtime";
    module_info.version = "1.0.0";
    module_info.description = "STT/TTS/VAD backend using ONNX Runtime";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_STT, RAC_CAPABILITY_TTS, RAC_CAPABILITY_VAD};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 3;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register strategies
    rac_storage_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_storage_strategy);
    rac_download_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_download_strategy);

    // Register STT provider
    rac_service_provider_t stt_provider = {};
    stt_provider.name = STT_PROVIDER_NAME;
    stt_provider.capability = RAC_CAPABILITY_STT;
    stt_provider.priority = 100;
    stt_provider.can_handle = onnx_stt_can_handle;
    stt_provider.create = onnx_stt_create;

    result = rac_service_register_provider(&stt_provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(MODULE_ID);
        return result;
    }

    // Register TTS provider
    rac_service_provider_t tts_provider = {};
    tts_provider.name = TTS_PROVIDER_NAME;
    tts_provider.capability = RAC_CAPABILITY_TTS;
    tts_provider.priority = 100;
    tts_provider.can_handle = onnx_tts_can_handle;
    tts_provider.create = onnx_tts_create;

    result = rac_service_register_provider(&tts_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
        rac_module_unregister(MODULE_ID);
        return result;
    }

    // Register VAD provider
    rac_service_provider_t vad_provider = {};
    vad_provider.name = VAD_PROVIDER_NAME;
    vad_provider.capability = RAC_CAPABILITY_VAD;
    vad_provider.priority = 100;
    vad_provider.can_handle = onnx_vad_can_handle;
    vad_provider.create = onnx_vad_create;

    result = rac_service_register_provider(&vad_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
        rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "ONNX backend registered (STT + TTS + VAD)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_model_strategy_unregister(RAC_FRAMEWORK_ONNX);
    rac_service_unregister_provider(VAD_PROVIDER_NAME, RAC_CAPABILITY_VAD);
    rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
    rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
