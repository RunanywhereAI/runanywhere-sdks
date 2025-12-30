/**
 * @file vad_component.cpp
 * @brief VAD Capability Component Implementation
 *
 * C++ port of Swift's VADCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/VAD/VADCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_energy.h"
#include "rac/features/vad/rac_vad_service.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_vad_component {
    /** Energy VAD service handle */
    rac_energy_vad_handle_t vad_service;

    /** Configuration */
    rac_vad_config_t config;

    /** Activity callback */
    rac_vad_activity_callback_fn activity_callback;
    void* activity_user_data;

    /** Audio callback */
    rac_vad_audio_callback_fn audio_callback;
    void* audio_user_data;

    /** Initialization state */
    bool is_initialized;

    /** Mutex for thread safety */
    std::mutex mtx;

    rac_vad_component()
        : vad_service(nullptr),
          activity_callback(nullptr),
          activity_user_data(nullptr),
          audio_callback(nullptr),
          audio_user_data(nullptr),
          is_initialized(false) {
        // Initialize with defaults - matches rac_vad_types.h rac_vad_config_t
        config = RAC_VAD_CONFIG_DEFAULT;
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

/**
 * Internal speech activity callback wrapper.
 * Routes events from energy VAD to the user callback.
 */
static void vad_speech_activity_callback(rac_speech_activity_event_t event, void* user_data) {
    auto* component = reinterpret_cast<rac_vad_component*>(user_data);
    if (!component)
        return;

    // Emit analytics event for speech activity
    rac_analytics_event_data_t event_data;
    event_data.data.vad = RAC_ANALYTICS_VAD_DEFAULT;

    if (event == RAC_SPEECH_ACTIVITY_STARTED) {
        // Emit VAD_SPEECH_STARTED event
        rac_analytics_event_emit(RAC_EVENT_VAD_SPEECH_STARTED, &event_data);
    } else {
        // Emit VAD_SPEECH_ENDED event
        rac_analytics_event_emit(RAC_EVENT_VAD_SPEECH_ENDED, &event_data);
    }

    // Route to user callback
    if (component->activity_callback) {
        rac_speech_activity_t activity{};
        if (event == RAC_SPEECH_ACTIVITY_STARTED) {
            activity = RAC_SPEECH_STARTED;
        } else {
            activity = RAC_SPEECH_ENDED;
        }
        component->activity_callback(activity, component->activity_user_data);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_vad_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_vad_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    log_info("VAD.Component", "VAD component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_vad_component_configure(rac_handle_t handle,
                                                    const rac_vad_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // ==========================================================================
    // VALIDATION - Ported from Swift VADConfiguration.swift:62-110
    // ==========================================================================

    // 1. Energy threshold range (Swift lines 64-69)
    if (config->energy_threshold < 0.0f || config->energy_threshold > 1.0f) {
        log_error("VAD.Component",
                  "Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // 2. Warning for very low threshold (Swift lines 72-77)
    if (config->energy_threshold < 0.002f) {
        rac_log(RAC_LOG_WARNING, "VAD.Component",
                "Energy threshold is very low (< 0.002) and may cause false positives");
    }

    // 3. Warning for very high threshold (Swift lines 80-85)
    if (config->energy_threshold > 0.1f) {
        rac_log(RAC_LOG_WARNING, "VAD.Component",
                "Energy threshold is very high (> 0.1) and may miss speech");
    }

    // 4. Sample rate validation (Swift lines 88-93)
    if (config->sample_rate < 1 || config->sample_rate > 48000) {
        log_error("VAD.Component", "Sample rate must be between 1 and 48000 Hz");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // 5. Frame length validation (Swift lines 96-101)
    if (config->frame_length <= 0.0f || config->frame_length > 1.0f) {
        log_error("VAD.Component", "Frame length must be between 0 and 1 second");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // 6. Calibration multiplier validation (Swift lines 104-109)
    // Note: Check if calibration_multiplier exists in config
    // Swift validates calibrationMultiplier >= 1.5 && <= 5.0

    // ==========================================================================

    component->config = *config;

    log_info("VAD.Component", "VAD component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_vad_component_is_initialized(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    return component->is_initialized ? RAC_TRUE : RAC_FALSE;
}

extern "C" rac_result_t rac_vad_component_initialize(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (component->is_initialized) {
        // Already initialized
        return RAC_SUCCESS;
    }

    // Create energy VAD configuration
    rac_energy_vad_config_t vad_config = {};
    vad_config.sample_rate = component->config.sample_rate;
    vad_config.frame_length = component->config.frame_length;
    vad_config.energy_threshold = component->config.energy_threshold;

    // Create energy VAD service
    rac_result_t result = rac_energy_vad_create(&vad_config, &component->vad_service);
    if (result != RAC_SUCCESS) {
        log_error("VAD.Component", "Failed to create energy VAD service");
        return result;
    }

    // Set speech callback
    result = rac_energy_vad_set_speech_callback(component->vad_service,
                                                vad_speech_activity_callback, component);
    if (result != RAC_SUCCESS) {
        rac_energy_vad_destroy(component->vad_service);
        component->vad_service = nullptr;
        return result;
    }

    // Initialize the VAD (starts calibration)
    result = rac_energy_vad_initialize(component->vad_service);
    if (result != RAC_SUCCESS) {
        log_error("VAD.Component", "Failed to initialize energy VAD service");
        rac_energy_vad_destroy(component->vad_service);
        component->vad_service = nullptr;
        return result;
    }

    component->is_initialized = true;

    log_info("VAD.Component", "VAD component initialized");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_vad_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (component->vad_service) {
        rac_energy_vad_stop(component->vad_service);
        rac_energy_vad_destroy(component->vad_service);
        component->vad_service = nullptr;
    }

    component->is_initialized = false;

    log_info("VAD.Component", "VAD component cleaned up");

    return RAC_SUCCESS;
}

extern "C" void rac_vad_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);

    // Cleanup first
    rac_vad_component_cleanup(handle);

    log_info("VAD.Component", "VAD component destroyed");

    delete component;
}

// =============================================================================
// CALLBACK API
// =============================================================================

extern "C" rac_result_t
rac_vad_component_set_activity_callback(rac_handle_t handle, rac_vad_activity_callback_fn callback,
                                        void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->activity_callback = callback;
    component->activity_user_data = user_data;

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_vad_component_set_audio_callback(rac_handle_t handle,
                                                             rac_vad_audio_callback_fn callback,
                                                             void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->audio_callback = callback;
    component->audio_user_data = user_data;

    return RAC_SUCCESS;
}

// =============================================================================
// CONTROL API
// =============================================================================

extern "C" rac_result_t rac_vad_component_start(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->is_initialized || !component->vad_service) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t result = rac_energy_vad_start(component->vad_service);

    if (result == RAC_SUCCESS) {
        // Emit VAD_STARTED event
        rac_analytics_event_data_t event_data;
        event_data.data.vad = RAC_ANALYTICS_VAD_DEFAULT;
        rac_analytics_event_emit(RAC_EVENT_VAD_STARTED, &event_data);
    }

    return result;
}

extern "C" rac_result_t rac_vad_component_stop(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->vad_service) {
        return RAC_SUCCESS;  // Already stopped
    }

    rac_result_t result = rac_energy_vad_stop(component->vad_service);

    if (result == RAC_SUCCESS) {
        // Emit VAD_STOPPED event
        rac_analytics_event_data_t event_data;
        event_data.data.vad = RAC_ANALYTICS_VAD_DEFAULT;
        rac_analytics_event_emit(RAC_EVENT_VAD_STOPPED, &event_data);
    }

    return result;
}

extern "C" rac_result_t rac_vad_component_reset(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->vad_service) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    return rac_energy_vad_reset(component->vad_service);
}

// =============================================================================
// PROCESSING API
// =============================================================================

extern "C" rac_result_t rac_vad_component_process(rac_handle_t handle, const float* samples,
                                                  size_t num_samples, rac_bool_t* out_is_speech) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!samples || num_samples == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->is_initialized || !component->vad_service) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Process audio through energy VAD
    rac_bool_t has_voice = RAC_FALSE;
    rac_result_t result =
        rac_energy_vad_process_audio(component->vad_service, samples, num_samples, &has_voice);

    if (result != RAC_SUCCESS) {
        return result;
    }

    if (out_is_speech) {
        *out_is_speech = has_voice;
    }

    // Route audio to audio callback if set
    if (component->audio_callback && samples) {
        component->audio_callback(samples, num_samples * sizeof(float), component->audio_user_data);
    }

    return RAC_SUCCESS;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_bool_t rac_vad_component_is_speech_active(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->vad_service) {
        return RAC_FALSE;
    }

    rac_bool_t is_active = RAC_FALSE;
    rac_energy_vad_is_speech_active(component->vad_service, &is_active);
    return is_active;
}

extern "C" float rac_vad_component_get_energy_threshold(rac_handle_t handle) {
    if (!handle)
        return 0.0f;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->vad_service) {
        return component->config.energy_threshold;
    }

    float threshold = 0.0f;
    rac_energy_vad_get_threshold(component->vad_service, &threshold);
    return threshold;
}

extern "C" rac_result_t rac_vad_component_set_energy_threshold(rac_handle_t handle,
                                                               float threshold) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    // Validation - Ported from Swift VADConfiguration.validate()
    if (threshold < 0.0f || threshold > 1.0f) {
        log_error("VAD.Component", "Threshold must be between 0.0 and 1.0");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Warning for edge cases
    if (threshold < 0.002f) {
        rac_log(RAC_LOG_WARNING, "VAD.Component",
                "Threshold is very low (< 0.002) and may cause false positives");
    }
    if (threshold > 0.1f) {
        rac_log(RAC_LOG_WARNING, "VAD.Component",
                "Threshold is very high (> 0.1) and may miss speech");
    }

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config.energy_threshold = threshold;

    if (component->vad_service) {
        return rac_energy_vad_set_threshold(component->vad_service, threshold);
    }

    return RAC_SUCCESS;
}

extern "C" rac_lifecycle_state_t rac_vad_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);

    if (component->is_initialized) {
        return RAC_LIFECYCLE_STATE_LOADED;
    }

    return RAC_LIFECYCLE_STATE_IDLE;
}

extern "C" rac_result_t rac_vad_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    // VAD doesn't use the standard lifecycle manager, so return basic metrics
    memset(out_metrics, 0, sizeof(rac_lifecycle_metrics_t));

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    if (component->is_initialized) {
        out_metrics->total_loads = 1;
        out_metrics->successful_loads = 1;
    }

    return RAC_SUCCESS;
}
