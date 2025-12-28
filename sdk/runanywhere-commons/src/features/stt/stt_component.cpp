/**
 * @file stt_component.cpp
 * @brief STT Capability Component Implementation
 *
 * C++ port of Swift's STTCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/STT/STTCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

/**
 * Internal STT component state.
 * Mirrors Swift's STTCapability actor state.
 */
struct rac_stt_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_stt_config_t config;

    /** Default transcription options based on config */
    rac_stt_options_t default_options;

    /** Mutex for thread safety */
    std::mutex mtx;

    rac_stt_component() : lifecycle(nullptr) {
        // Initialize with defaults - matches rac_stt_types.h rac_stt_config_t
        config = RAC_STT_CONFIG_DEFAULT;

        default_options = RAC_STT_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static void log_info(const char* category, const char* msg) {
    rac_log(RAC_LOG_INFO, category, msg);
}

static void log_error(const char* category, const char* msg) {
    rac_log(RAC_LOG_ERROR, category, msg);
}

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

static rac_result_t stt_create_service(const char* model_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    log_info("STT.Component", "Creating STT service");

    // Create STT service
    rac_result_t result = rac_stt_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Failed to create STT service");
        return result;
    }

    // Initialize with model path
    result = rac_stt_initialize(*out_service, model_id);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Failed to initialize STT service");
        rac_stt_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    log_info("STT.Component", "STT service created successfully");
    return RAC_SUCCESS;
}

static void stt_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        log_info("STT.Component", "Destroying STT service");
        rac_stt_cleanup(service);
        rac_stt_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_stt_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_stt_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_STT_MODEL;
    lifecycle_config.logger_category = "STT.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, stt_create_service,
                                               stt_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    log_info("STT.Component", "STT component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_stt_component_configure(rac_handle_t handle,
                                                    const rac_stt_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    // Update default options based on config
    if (config->language) {
        component->default_options.language = config->language;
    }
    component->default_options.sample_rate = config->sample_rate;
    component->default_options.enable_punctuation = config->enable_punctuation;
    component->default_options.enable_timestamps = config->enable_timestamps;

    log_info("STT.Component", "STT component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_stt_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_stt_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_stt_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);

    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    log_info("STT.Component", "STT component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_stt_component_load_model(rac_handle_t handle, const char* model_id) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_id, &service);
}

extern "C" rac_result_t rac_stt_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_stt_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

// =============================================================================
// TRANSCRIPTION API
// =============================================================================

extern "C" rac_result_t rac_stt_component_transcribe(rac_handle_t handle, const void* audio_data,
                                                     size_t audio_size,
                                                     const rac_stt_options_t* options,
                                                     rac_stt_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "No model loaded - cannot transcribe");
        return result;
    }

    log_info("STT.Component", "Transcribing audio");

    const rac_stt_options_t* effective_options = options ? options : &component->default_options;

    auto start_time = std::chrono::steady_clock::now();

    result = rac_stt_transcribe(service, audio_data, audio_size, effective_options, out_result);

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribe");
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    // Update metrics if not already set
    if (out_result->processing_time_ms == 0) {
        out_result->processing_time_ms = duration.count();
    }

    log_info("STT.Component", "Transcription completed");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_stt_component_supports_streaming(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_FALSE;
    }

    rac_stt_info_t info;
    rac_result_t result = rac_stt_get_info(service, &info);
    if (result != RAC_SUCCESS) {
        return RAC_FALSE;
    }

    return info.supports_streaming;
}

extern "C" rac_result_t
rac_stt_component_transcribe_stream(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                    const rac_stt_options_t* options,
                                    rac_stt_stream_callback_t callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "No model loaded - cannot transcribe stream");
        return result;
    }

    // Check if streaming is supported
    rac_stt_info_t info;
    result = rac_stt_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        log_error("STT.Component", "Streaming not supported");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    log_info("STT.Component", "Starting streaming transcription");

    const rac_stt_options_t* effective_options = options ? options : &component->default_options;

    result = rac_stt_transcribe_stream(service, audio_data, audio_size, effective_options, callback,
                                       user_data);

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Streaming transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribeStream");
    }

    return result;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_stt_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_stt_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}
