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
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
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

/**
 * Generate a unique ID for transcription tracking.
 */
static std::string generate_unique_id() {
    auto now = std::chrono::high_resolution_clock::now();
    auto epoch = now.time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(epoch).count();
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "trans_%lld", static_cast<long long>(ns));
    return std::string(buffer);
}

/**
 * Count words in text.
 */
static int32_t count_words(const char* text) {
    if (!text)
        return 0;
    int32_t count = 0;
    bool in_word = false;
    while (*text != '\0') {
        if (*text == ' ' || *text == '\t' || *text == '\n') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count++;
        }
        text++;
    }
    return count;
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

extern "C" rac_result_t rac_stt_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* model_id, const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
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

    // Generate unique ID for this transcription
    std::string transcription_id = generate_unique_id();
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Debug: Log if model_id is null
    if (!model_id) {
        log_warning(
            "STT.Component",
            "rac_lifecycle_get_model_id returned null - model_id may not be set in telemetry");
    } else {
        log_debug("STT.Component", "STT transcription using model_id: %s", model_id);
    }

    // Estimate audio length (assuming 16kHz mono 16-bit audio)
    double audio_length_ms = (audio_size / 2.0 / 16000.0) * 1000.0;

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "No model loaded - cannot transcribe");

        // Emit transcription failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.error_code = result;
        event.data.stt_transcription.error_message = "No model loaded";
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);

        return result;
    }

    log_info("STT.Component", "Transcribing audio");

    const rac_stt_options_t* effective_options = options ? options : &component->default_options;

    // Emit transcription started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_STARTED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.is_streaming = RAC_FALSE;
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework =
            static_cast<rac_inference_framework_t>(component->config.preferred_framework);
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_STARTED, &event);
    }

    auto start_time = std::chrono::steady_clock::now();

    result = rac_stt_transcribe(service, audio_data, audio_size, effective_options, out_result);

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribe");

        // Emit transcription failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.error_code = result;
        event.data.stt_transcription.error_message = "Transcription failed";
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);

        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    double duration_ms = static_cast<double>(duration.count());

    // Update metrics if not already set
    if (out_result->processing_time_ms == 0) {
        out_result->processing_time_ms = duration.count();
    }

    // Calculate word count and real-time factor
    int32_t word_count = count_words(out_result->text);
    double real_time_factor =
        (audio_length_ms > 0 && duration_ms > 0) ? (audio_length_ms / duration_ms) : 0.0;

    log_info("STT.Component", "Transcription completed");

    // Emit transcription completed event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_COMPLETED;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.text = out_result->text;
        event.data.stt_transcription.confidence = out_result->confidence;
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.word_count = word_count;
        event.data.stt_transcription.real_time_factor = real_time_factor;
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework =
            static_cast<rac_inference_framework_t>(component->config.preferred_framework);
        event.data.stt_transcription.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_COMPLETED, &event);
    }

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

    // Get model info for telemetry - use lifecycle methods for consistency with non-streaming path
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Debug: Log if model_id is null
    if (!model_id) {
        log_warning(
            "STT.Component",
            "rac_lifecycle_get_model_id returned null - model_id may not be set in telemetry");
    } else {
        log_debug("STT.Component", "STT streaming transcription using model_id: %s", model_id);
    }

    // Calculate audio length in ms (assume 16kHz, 16-bit mono)
    double audio_length_ms = (audio_size * 1000.0) / (component->config.sample_rate * 2);

    // Generate transcription ID for tracking
    std::string transcription_id = generate_unique_id();

    // Emit STT_TRANSCRIPTION_STARTED event with is_streaming = RAC_TRUE
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_STARTED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.is_streaming = RAC_TRUE;  // Streaming mode!
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework =
            static_cast<rac_inference_framework_t>(component->config.preferred_framework);
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_STARTED, &event);
    }

    auto start_time = std::chrono::steady_clock::now();

    result = rac_stt_transcribe_stream(service, audio_data, audio_size, effective_options, callback,
                                       user_data);

    auto end_time = std::chrono::steady_clock::now();
    double duration_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Streaming transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribeStream");

        // Emit STT_TRANSCRIPTION_FAILED event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.is_streaming = RAC_TRUE;
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.error_code = result;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);
    } else {
        // Emit STT_TRANSCRIPTION_COMPLETED event with is_streaming = RAC_TRUE
        // Note: For streaming, we don't have final consolidated text, so word_count is not
        // available. We can still compute real_time_factor from audio_length_ms and duration_ms.
        double real_time_factor =
            (audio_length_ms > 0 && duration_ms > 0) ? (audio_length_ms / duration_ms) : 0.0;

        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_COMPLETED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.is_streaming = RAC_TRUE;  // Streaming mode!
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.real_time_factor = real_time_factor;
        // word_count not available for streaming - text is delivered via callbacks
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework =
            static_cast<rac_inference_framework_t>(component->config.preferred_framework);
        event.data.stt_transcription.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_COMPLETED, &event);
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
