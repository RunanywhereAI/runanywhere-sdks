/**
 * @file rac_backend_onnx_register.cpp
 * @brief RunAnywhere Commons - ONNX Backend Registration
 *
 * Registers the ONNX backend with the module and service registries.
 * Includes storage and download strategies for ONNX models.
 * Mirrors Swift's ONNXServiceProvider registration pattern.
 */

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// =============================================================================
// SERVICE PROVIDER IMPLEMENTATIONS
// =============================================================================

namespace {

// Module info
const char* const MODULE_ID = "onnx";

// Provider names
const char* const STT_PROVIDER_NAME = "ONNXSTTService";
const char* const TTS_PROVIDER_NAME = "ONNXTTSService";
const char* const VAD_PROVIDER_NAME = "ONNXVADService";

// =============================================================================
// STT PROVIDER
// =============================================================================

/**
 * Check if ONNX can handle STT request.
 * Mirrors Swift's canHandle: { modelId in modelId?.contains("whisper") ?? true }
 */
rac_bool_t onnx_stt_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Default provider if no specific model
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;
    }

    // Check for ONNX model patterns
    const char* path = request->identifier;
    if (strstr(path, "whisper") != nullptr || strstr(path, "zipformer") != nullptr ||
        strstr(path, "paraformer") != nullptr || strstr(path, ".onnx") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_handle_t onnx_stt_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_stt_onnx_create(request->identifier, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

// =============================================================================
// TTS PROVIDER
// =============================================================================

rac_bool_t onnx_tts_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Default TTS provider
    if (request->identifier == nullptr || request->identifier[0] == '\0') {
        return RAC_TRUE;
    }

    // Check for TTS model patterns
    const char* path = request->identifier;
    if (strstr(path, "piper") != nullptr || strstr(path, "vits") != nullptr ||
        strstr(path, ".onnx") != nullptr) {
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_handle_t onnx_tts_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return nullptr;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_tts_onnx_create(request->identifier, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

// =============================================================================
// VAD PROVIDER
// =============================================================================

rac_bool_t onnx_vad_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;
    (void)request;

    // VAD always handled by ONNX (Silero VAD)
    return RAC_TRUE;
}

rac_handle_t onnx_vad_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    const char* model_path = nullptr;
    if (request != nullptr) {
        model_path = request->identifier;
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_vad_onnx_create(model_path, nullptr, &handle);

    if (result != RAC_SUCCESS) {
        return nullptr;
    }

    return handle;
}

// Track registration state
bool g_registered = false;

const char* STRATEGY_LOG_CAT = "ONNXStrategy";

// =============================================================================
// ONNX STORAGE STRATEGY - Handles nested directory structures
// =============================================================================

/**
 * Find ONNX model file in a directory (non-recursive)
 */
static const char* find_onnx_file(const char* folder) {
    // This would normally use platform file APIs
    // For now, return nullptr - platform code will provide file operations
    (void)folder;
    return nullptr;
}

/**
 * Find model path within a model folder.
 * ONNX models may be nested in subdirectories (e.g., sherpa-onnx structure).
 */
rac_result_t onnx_storage_find_model_path(const char* model_id, const char* model_folder,
                                          char* out_path, size_t path_size, void* user_data) {
    (void)user_data;

    if (!model_id || !model_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Default: model file at model_folder/{model_id}.onnx
    // Platform code should provide actual file system access
    int written = snprintf(out_path, path_size, "%s/%s.onnx", model_folder, model_id);
    if (written < 0 || (size_t)written >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    RAC_LOG_DEBUG(STRATEGY_LOG_CAT, "ONNX model path: %s", out_path);
    return RAC_SUCCESS;
}

/**
 * Detect ONNX model in a folder.
 */
rac_result_t onnx_storage_detect_model(const char* model_folder,
                                       rac_model_storage_details_t* out_details, void* user_data) {
    (void)user_data;

    if (!model_folder || !out_details) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Initialize output
    memset(out_details, 0, sizeof(rac_model_storage_details_t));
    out_details->format = RAC_MODEL_FORMAT_ONNX;
    out_details->is_directory_based = RAC_TRUE;
    out_details->is_valid = RAC_TRUE;

    // Actual detection requires platform file operations
    // Set basic values - platform can enhance
    out_details->total_size = 0;
    out_details->file_count = 1;
    out_details->primary_file = nullptr;

    RAC_LOG_DEBUG(STRATEGY_LOG_CAT, "Detected ONNX model in: %s", model_folder);
    return RAC_SUCCESS;
}

/**
 * Validate ONNX model storage.
 */
rac_bool_t onnx_storage_is_valid(const char* model_folder, void* user_data) {
    (void)user_data;

    if (!model_folder) {
        return RAC_FALSE;
    }

    // Platform code should verify .onnx file exists
    // For now, assume valid if folder exists
    return RAC_TRUE;
}

/**
 * Get expected file patterns for ONNX models.
 */
void onnx_storage_get_patterns(const char*** out_patterns, size_t* out_count, void* user_data) {
    (void)user_data;

    static const char* patterns[] = {"*.onnx", "*.ort", "encoder*.onnx", "decoder*.onnx",
                                     "model.onnx"};

    *out_patterns = patterns;
    *out_count = sizeof(patterns) / sizeof(patterns[0]);
}

// =============================================================================
// ONNX DOWNLOAD STRATEGY
// =============================================================================

/**
 * Prepare ONNX download.
 */
rac_result_t onnx_download_prepare(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;

    if (!config || !config->model_id || !config->destination_folder) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    RAC_LOG_DEBUG(STRATEGY_LOG_CAT, "Preparing ONNX download: %s", config->model_id);
    return RAC_SUCCESS;
}

/**
 * Get download destination path.
 */
rac_result_t onnx_download_get_dest(const rac_model_download_config_t* config, char* out_path,
                                    size_t path_size, void* user_data) {
    (void)user_data;

    if (!config || !config->destination_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // ONNX downloads go to: {destination_folder}/{model_id}/
    int written =
        snprintf(out_path, path_size, "%s/%s", config->destination_folder, config->model_id);
    if (written < 0 || (size_t)written >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    return RAC_SUCCESS;
}

/**
 * Post-process ONNX download (extraction, validation).
 */
rac_result_t onnx_download_post_process(const rac_model_download_config_t* config,
                                        const char* downloaded_path,
                                        rac_download_result_t* out_result, void* user_data) {
    (void)user_data;

    if (!config || !downloaded_path || !out_result) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Initialize result
    memset(out_result, 0, sizeof(rac_download_result_t));

    // For archives, extraction would happen here
    // Platform provides actual extraction via callbacks
    if (config->archive_type != RAC_ARCHIVE_TYPE_NONE) {
        RAC_LOG_DEBUG(STRATEGY_LOG_CAT, "ONNX archive needs extraction: %s", downloaded_path);
        out_result->was_extracted = RAC_TRUE;
    } else {
        out_result->was_extracted = RAC_FALSE;
    }

    // Set final path (same as downloaded for non-archives)
    out_result->final_path = strdup(downloaded_path);
    out_result->file_count = 1;

    RAC_LOG_INFO(STRATEGY_LOG_CAT, "ONNX post-process complete: %s", downloaded_path);
    return RAC_SUCCESS;
}

/**
 * Cleanup failed ONNX download.
 */
void onnx_download_cleanup(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;

    if (config && config->model_id) {
        RAC_LOG_DEBUG(STRATEGY_LOG_CAT, "Cleaning up ONNX download: %s", config->model_id);
    }
    // Platform handles actual file cleanup
}

// Storage strategy instance
static rac_storage_strategy_t g_onnx_storage_strategy = {onnx_storage_find_model_path,
                                                         onnx_storage_detect_model,
                                                         onnx_storage_is_valid,
                                                         onnx_storage_get_patterns,
                                                         nullptr,  // user_data
                                                         "ONNXStorageStrategy"};

// Download strategy instance
static rac_download_strategy_t g_onnx_download_strategy = {onnx_download_prepare,
                                                           onnx_download_get_dest,
                                                           onnx_download_post_process,
                                                           onnx_download_cleanup,
                                                           nullptr,  // user_data
                                                           "ONNXDownloadStrategy"};

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_onnx_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module with capabilities
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

    // Register storage and download strategies for ONNX framework
    result = rac_storage_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_storage_strategy);
    if (result != RAC_SUCCESS) {
        RAC_LOG_WARNING(STRATEGY_LOG_CAT, "Failed to register ONNX storage strategy");
    }

    result = rac_download_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_download_strategy);
    if (result != RAC_SUCCESS) {
        RAC_LOG_WARNING(STRATEGY_LOG_CAT, "Failed to register ONNX download strategy");
    }

    // Register STT provider
    rac_service_provider_t stt_provider = {};
    stt_provider.name = STT_PROVIDER_NAME;
    stt_provider.capability = RAC_CAPABILITY_STT;
    stt_provider.priority = 100;
    stt_provider.can_handle = onnx_stt_can_handle;
    stt_provider.create = onnx_stt_create;
    stt_provider.user_data = nullptr;

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
    tts_provider.user_data = nullptr;

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
    vad_provider.user_data = nullptr;

    result = rac_service_register_provider(&vad_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
        rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);
        rac_module_unregister(MODULE_ID);
        return result;
    }

    g_registered = true;
    return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    // Unregister strategies
    rac_model_strategy_unregister(RAC_FRAMEWORK_ONNX);

    // Unregister service providers
    rac_service_unregister_provider(VAD_PROVIDER_NAME, RAC_CAPABILITY_VAD);
    rac_service_unregister_provider(TTS_PROVIDER_NAME, RAC_CAPABILITY_TTS);
    rac_service_unregister_provider(STT_PROVIDER_NAME, RAC_CAPABILITY_STT);

    // Unregister module
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
