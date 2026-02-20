/**
 * @file tts_component.cpp
 * @brief TTS Capability Component Implementation
 *
 * C++ port of Swift's TTSCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/TTS/TTSCapability.swift
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
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_tts_component {
    rac_handle_t lifecycle;
    rac_tts_config_t config;
    rac_tts_options_t default_options;
    std::mutex mtx;

    /** Resolved inference framework (defaults to ONNX, the primary TTS backend) */
    rac_inference_framework_t actual_framework;

    rac_tts_component() : lifecycle(nullptr), actual_framework(RAC_FRAMEWORK_ONNX) {
        // Initialize with defaults - matches rac_tts_types.h rac_tts_config_t
        config = RAC_TTS_CONFIG_DEFAULT;

        default_options = RAC_TTS_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Generate a simple UUID v4-like string for event tracking
static std::string generate_uuid_v4() {
    static const char* hex = "0123456789abcdef";
    std::string uuid = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";
    for (size_t i = 0; i < uuid.size(); i++) {
        if (uuid[i] == 'x') {
            uuid[i] = hex[std::rand() % 16];
        } else if (uuid[i] == 'y') {
            uuid[i] = hex[(std::rand() % 4) + 8];
        }
    }
    return uuid;
}

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

static rac_result_t tts_create_service(const char* voice_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    log_info("TTS.Component", "Creating TTS service");

    rac_result_t result = rac_tts_create(voice_id, out_service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Failed to create TTS service");
        return result;
    }

    result = rac_tts_initialize(*out_service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Failed to initialize TTS service");
        rac_tts_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    log_info("TTS.Component", "TTS service created successfully");
    return RAC_SUCCESS;
}

static void tts_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        log_info("TTS.Component", "Destroying TTS service");
        rac_tts_cleanup(service);
        rac_tts_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_tts_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_tts_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_TTS_VOICE;
    lifecycle_config.logger_category = "TTS.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, tts_create_service,
                                               tts_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    log_info("TTS.Component", "TTS component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tts_component_configure(rac_handle_t handle,
                                                    const rac_tts_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    // Resolve actual framework: if caller explicitly set one (not -1=auto), use it;
    // otherwise keep the default (RAC_FRAMEWORK_ONNX for TTS components)
    if (config->preferred_framework >= 0 &&
        config->preferred_framework != static_cast<int32_t>(RAC_FRAMEWORK_UNKNOWN)) {
        component->actual_framework =
            static_cast<rac_inference_framework_t>(config->preferred_framework);
    }

    // Update default options based on config - matches rac_tts_config_t fields
    if (config->speaking_rate > 0) {
        component->default_options.rate = config->speaking_rate;
    }
    if (config->pitch > 0) {
        component->default_options.pitch = config->pitch;
    }
    if (config->volume > 0) {
        component->default_options.volume = config->volume;
    }
    if (config->language) {
        component->default_options.language = config->language;
    }
    if (config->voice) {
        component->default_options.voice = config->voice;
    }
    component->default_options.use_ssml = config->enable_ssml;

    log_info("TTS.Component", "TTS component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_tts_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_tts_component_get_voice_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_tts_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);

    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    log_info("TTS.Component", "TTS component destroyed");

    delete component;
}

// =============================================================================
// VOICE LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_tts_component_load_voice(rac_handle_t handle, const char* voice_path,
                                                     const char* voice_id, const char* voice_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Emit voice load started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_STARTED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_STARTED, &event);
    }

    auto load_start = std::chrono::steady_clock::now();

    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, voice_path, voice_id, voice_name, &service);

    double load_duration_ms = static_cast<double>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() -
                                                              load_start)
            .count());

    if (result != RAC_SUCCESS) {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_FAILED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = result;
        event.data.llm_model.error_message = "Voice load failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_FAILED, &event);
    } else {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_COMPLETED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_COMPLETED, &event);
    }

    return result;
}

extern "C" rac_result_t rac_tts_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_stop(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (service) {
        rac_tts_stop(service);
    }

    log_info("TTS.Component", "Synthesis stop requested");

    return RAC_SUCCESS;
}

// =============================================================================
// SYNTHESIS API
// =============================================================================

extern "C" rac_result_t rac_tts_component_synthesize(rac_handle_t handle, const char* text,
                                                     const rac_tts_options_t* options,
                                                     rac_tts_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Generate synthesis ID for event tracking
    std::string synthesis_id = generate_uuid_v4();
    const char* voice_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* voice_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Debug: Log if voice_id is null
    if (!voice_id) {
        log_warning("TTS.Component",
                    "rac_lifecycle_get_model_id returned null - voice may not be set in telemetry");
    } else {
        log_debug("TTS.Component", "TTS synthesis using voice_id: %s", voice_id);
    }

    // Emit SYNTHESIS_STARTED event
    {
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = static_cast<int32_t>(std::strlen(text));
        event_data.data.tts_synthesis.framework = component->actual_framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_STARTED, &event_data);
    }

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "No voice loaded - cannot synthesize");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.framework = component->actual_framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "No voice loaded";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
        return result;
    }

    log_info("TTS.Component", "Synthesizing text");

    const rac_tts_options_t* effective_options = options ? options : &component->default_options;

    auto start_time = std::chrono::steady_clock::now();

    result = rac_tts_synthesize(service, text, effective_options, out_result);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesize");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.processing_duration_ms =
            static_cast<double>(duration.count());
        event_data.data.tts_synthesis.framework = component->actual_framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "Synthesis failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
        return result;
    }

    if (out_result->processing_time_ms == 0) {
        out_result->processing_time_ms = duration.count();
    }

    // Emit SYNTHESIS_COMPLETED event
    {
        int32_t char_count = static_cast<int32_t>(std::strlen(text));
        double processing_ms = static_cast<double>(out_result->processing_time_ms);
        double chars_per_sec = processing_ms > 0 ? (char_count * 1000.0 / processing_ms) : 0.0;

        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.audio_duration_ms =
            static_cast<double>(out_result->duration_ms);
        event_data.data.tts_synthesis.audio_size_bytes =
            static_cast<int32_t>(out_result->audio_size);
        event_data.data.tts_synthesis.processing_duration_ms = processing_ms;
        event_data.data.tts_synthesis.characters_per_second = chars_per_sec;
        event_data.data.tts_synthesis.sample_rate = static_cast<int32_t>(out_result->sample_rate);
        event_data.data.tts_synthesis.framework = component->actual_framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_COMPLETED, &event_data);
    }

    log_info("TTS.Component", "Synthesis completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tts_component_synthesize_stream(rac_handle_t handle, const char* text,
                                                            const rac_tts_options_t* options,
                                                            rac_tts_stream_callback_t callback,
                                                            void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Generate synthesis ID for event tracking
    std::string synthesis_id = generate_uuid_v4();
    const char* voice_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* voice_name = rac_lifecycle_get_model_name(component->lifecycle);
    int32_t char_count = static_cast<int32_t>(std::strlen(text));

    // Emit SYNTHESIS_STARTED event
    {
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.framework = component->actual_framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_STARTED, &event_data);
    }

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "No voice loaded - cannot synthesize stream");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.framework = component->actual_framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "No voice loaded";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
        return result;
    }

    log_info("TTS.Component", "Starting streaming synthesis");

    const rac_tts_options_t* effective_options = options ? options : &component->default_options;

    auto start_time = std::chrono::steady_clock::now();

    result = rac_tts_synthesize_stream(service, text, effective_options, callback, user_data);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Streaming synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesizeStream");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.processing_duration_ms =
            static_cast<double>(duration.count());
        event_data.data.tts_synthesis.framework = component->actual_framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "Streaming synthesis failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
    } else {
        // Emit SYNTHESIS_COMPLETED event (streaming complete)
        double processing_ms = static_cast<double>(duration.count());
        double chars_per_sec = processing_ms > 0 ? (char_count * 1000.0 / processing_ms) : 0.0;

        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.processing_duration_ms = processing_ms;
        event_data.data.tts_synthesis.characters_per_second = chars_per_sec;
        event_data.data.tts_synthesis.framework = component->actual_framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_COMPLETED, &event_data);
    }

    return result;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_tts_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}
