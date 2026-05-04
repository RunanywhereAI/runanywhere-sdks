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

#include <atomic>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_energy.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "vad_options.pb.h"
#include "voice_events.pb.h"
#endif

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_vad_component {
    /** Energy VAD service handle (built-in fallback) */
    rac_energy_vad_handle_t vad_service;

    /** Model-loaded VAD service (from service registry, e.g. ONNX Silero) */
    rac_vad_service_t* model_service;

    /** Whether a model-based VAD service is loaded */
    bool is_model_loaded;

    /** Loaded model ID */
    char* loaded_model_id;

    /** Configuration */
    rac_vad_config_t config;

    /** Activity callback */
    rac_vad_activity_callback_fn activity_callback;
    void* activity_user_data;

    /** Audio callback */
    rac_vad_audio_callback_fn audio_callback;
    void* audio_user_data;

    /** Initialization state (atomic for lock-free query from callbacks) */
    std::atomic<bool> is_initialized;

    /** Mutex for thread safety */
    std::mutex mtx;

    rac_vad_component()
        : vad_service(nullptr),
          model_service(nullptr),
          is_model_loaded(false),
          loaded_model_id(nullptr),
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

namespace {

#if defined(RAC_HAVE_PROTOBUF)

struct ProtoActivitySlot {
    rac_vad_proto_activity_callback_fn callback{nullptr};
    void* user_data{nullptr};
};

std::mutex& proto_activity_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::unordered_map<rac_handle_t, ProtoActivitySlot>& proto_activity_slots() {
    static std::unordered_map<rac_handle_t, ProtoActivitySlot> slots;
    return slots;
}

bool proto_bytes_valid(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* proto_parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize VAD proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

float compute_rms_energy(const float* samples, size_t count) {
    if (!samples || count == 0) {
        return 0.0f;
    }
    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        sum += static_cast<double>(samples[i]) * static_cast<double>(samples[i]);
    }
    return static_cast<float>(std::sqrt(sum / static_cast<double>(count)));
}

runanywhere::v1::SpeechActivityKind speech_activity_kind(rac_speech_activity_t activity) {
    switch (activity) {
        case RAC_SPEECH_STARTED:
            return runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_STARTED;
        case RAC_SPEECH_ENDED:
            return runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_ENDED;
        case RAC_SPEECH_ONGOING:
            return runanywhere::v1::SPEECH_ACTIVITY_KIND_ONGOING;
        default:
            return runanywhere::v1::SPEECH_ACTIVITY_KIND_UNSPECIFIED;
    }
}

void publish_vad_pipeline_event(bool is_speech,
                                float confidence,
                                float energy,
                                int32_t duration_ms,
                                rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::VoiceEvent voice_event;
    voice_event.set_timestamp_us(rac_get_current_time_ms() * 1000);
    voice_event.set_category(error_code == RAC_SUCCESS
                                 ? runanywhere::v1::VOICE_EVENT_CATEGORY_VAD
                                 : runanywhere::v1::VOICE_EVENT_CATEGORY_ERROR);
    voice_event.set_severity(error_code == RAC_SUCCESS
                                 ? runanywhere::v1::VOICE_EVENT_SEVERITY_INFO
                                 : runanywhere::v1::VOICE_EVENT_SEVERITY_ERROR);
    voice_event.set_component(runanywhere::v1::VOICE_PIPELINE_COMPONENT_VAD);
    if (error_code == RAC_SUCCESS) {
        auto* vad = voice_event.mutable_vad();
        vad->set_type(is_speech ? runanywhere::v1::VAD_EVENT_VOICE_START
                                : runanywhere::v1::VAD_EVENT_SILENCE);
        vad->set_confidence(confidence);
        vad->set_is_speech(is_speech);
        vad->set_speech_duration_ms(is_speech ? duration_ms : 0);
        vad->set_silence_duration_ms(is_speech ? 0 : duration_ms);
        vad->set_noise_floor_db(energy > 0.0f ? 20.0 * std::log10(energy) : -120.0);
    } else {
        auto* error = voice_event.mutable_error();
        error->set_code(static_cast<int32_t>(error_code));
        error->set_message(rac_error_message(error_code));
        error->set_component("vad");
        error->set_is_recoverable(true);
    }

    runanywhere::v1::SDKEvent sdk_event;
    sdk_event.set_timestamp_ms(rac_get_current_time_ms());
    sdk_event.set_id("vad-" + std::to_string(sdk_event.timestamp_ms()));
    sdk_event.set_category(error_code == RAC_SUCCESS ? runanywhere::v1::EVENT_CATEGORY_VAD
                                                     : runanywhere::v1::EVENT_CATEGORY_FAILURE);
    sdk_event.set_component(runanywhere::v1::SDK_COMPONENT_VAD);
    sdk_event.set_severity(error_code == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                                                     : runanywhere::v1::EVENT_SEVERITY_ERROR);
    sdk_event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    sdk_event.mutable_voice_pipeline()->CopyFrom(voice_event);
    const size_t size = sdk_event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 ||
        sdk_event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void proto_activity_trampoline(rac_speech_activity_t activity, void* user_data) {
    const rac_handle_t handle = reinterpret_cast<rac_handle_t>(user_data);
    ProtoActivitySlot slot;
    {
        std::lock_guard<std::mutex> lock(proto_activity_mutex());
        auto it = proto_activity_slots().find(handle);
        if (it == proto_activity_slots().end() || !it->second.callback) {
            return;
        }
        slot = it->second;
    }

    runanywhere::v1::SpeechActivityEvent event;
    event.set_event_type(speech_activity_kind(activity));
    event.set_timestamp_ms(rac_get_current_time_ms());
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 ||
        event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        slot.callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), slot.user_data);
    }
}

void clear_proto_activity_slot(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(proto_activity_mutex());
    proto_activity_slots().erase(handle);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

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
        RAC_LOG_WARNING("VAD.Component",
                        "Energy threshold is very low (< 0.002) and may cause false positives");
    }

    // 3. Warning for very high threshold (Swift lines 80-85)
    if (config->energy_threshold > 0.1f) {
        RAC_LOG_WARNING("VAD.Component",
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
    return component->is_initialized.load(std::memory_order_acquire) ? RAC_TRUE : RAC_FALSE;
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

    // Clean up model-loaded VAD service
    if (component->model_service) {
        if (component->model_service->ops && component->model_service->ops->destroy) {
            component->model_service->ops->destroy(component->model_service->impl);
        }
        free(const_cast<char*>(component->model_service->model_id));
        free(component->model_service);
        component->model_service = nullptr;
    }
    component->is_model_loaded = false;
    free(component->loaded_model_id);
    component->loaded_model_id = nullptr;

    // Clean up energy VAD service
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

#if defined(RAC_HAVE_PROTOBUF)
    clear_proto_activity_slot(handle);
#endif

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
// MODEL LOADING API
// =============================================================================

extern "C" rac_result_t rac_vad_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* model_id, const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!model_path)
        return RAC_ERROR_INVALID_ARGUMENT;

    (void)model_name;  // Reserved for future use

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Unload any previously loaded model
    if (component->model_service) {
        if (component->model_service->ops && component->model_service->ops->destroy) {
            component->model_service->ops->destroy(component->model_service->impl);
        }
        free(const_cast<char*>(component->model_service->model_id));
        free(component->model_service);
        component->model_service = nullptr;
    }
    component->is_model_loaded = false;
    free(component->loaded_model_id);
    component->loaded_model_id = nullptr;

    // v3 Phase B8: route through the plugin registry.
    // VAD doesn't take a framework hint from the model_info registry
    // today (Swift VADCapability only passes model_path), so we rely
    // purely on format/priority scoring. onnx_vad (priority 100) will
    // win for model-based VAD; energy VAD is not plugin-registered
    // since it's not a full ops-based engine.
    const rac_engine_vtable_t* vt = nullptr;
    rac_result_t result = rac_plugin_route(RAC_PRIMITIVE_DETECT_VOICE,
                                           /*format=*/0,
                                           /*hints=*/nullptr, &vt);
    if (result != RAC_SUCCESS || !vt || !vt->vad_ops || !vt->vad_ops->create) {
        log_error("VAD.Component", "rac_plugin_route failed for VAD");
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_FOUND;
    }

    void* impl = nullptr;
    result = vt->vad_ops->create(model_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        log_error("VAD.Component", "Plugin create failed for VAD");
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_vad_service_t*>(malloc(sizeof(rac_vad_service_t)));
    if (!service) {
        if (vt->vad_ops->destroy) vt->vad_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->vad_ops;
    service->impl = impl;
    service->model_id = model_path ? strdup(model_path) : nullptr;
    rac_handle_t service_handle = service;

    // The service registry returns a rac_vad_service_t* (vtable-wrapped)
    component->model_service = reinterpret_cast<rac_vad_service_t*>(service_handle);
    component->is_model_loaded = true;
    component->loaded_model_id = model_id ? strdup(model_id) : nullptr;

    // Start the model-based VAD. If start fails, roll back so `is_model_loaded`
    // does not lie about a non-running service.
    if (component->model_service->ops && component->model_service->ops->start) {
        result = component->model_service->ops->start(component->model_service->impl);
        if (result != RAC_SUCCESS) {
            log_error("VAD.Component", "Model VAD start failed: %d — rolling back load", result);
            if (component->model_service->ops->destroy) {
                component->model_service->ops->destroy(component->model_service->impl);
            }
            free(const_cast<char*>(component->model_service->model_id));
            free(component->model_service);
            component->model_service = nullptr;
            component->is_model_loaded = false;
            free(component->loaded_model_id);
            component->loaded_model_id = nullptr;
            return result;
        }
    }

    log_info("VAD.Component", "VAD model loaded: %s", model_id ? model_id : "unknown");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_vad_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    return component->is_model_loaded ? RAC_TRUE : RAC_FALSE;
}

extern "C" rac_result_t rac_vad_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    if (!component->model_service) {
        return RAC_SUCCESS;  // Nothing to unload
    }

    if (component->model_service->ops && component->model_service->ops->stop) {
        component->model_service->ops->stop(component->model_service->impl);
    }
    if (component->model_service->ops && component->model_service->ops->destroy) {
        component->model_service->ops->destroy(component->model_service->impl);
    }
    free(const_cast<char*>(component->model_service->model_id));
    free(component->model_service);
    component->model_service = nullptr;
    component->is_model_loaded = false;
    free(component->loaded_model_id);
    component->loaded_model_id = nullptr;

    log_info("VAD.Component", "VAD model unloaded, reverted to energy VAD");

    return RAC_SUCCESS;
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

    rac_bool_t has_voice = RAC_FALSE;
    rac_result_t result;

    // Dispatch through model service if loaded (e.g., Silero via ONNX)
    if (component->is_model_loaded && component->model_service && component->model_service->ops &&
        component->model_service->ops->process) {
        result = component->model_service->ops->process(component->model_service->impl, samples,
                                                        num_samples, &has_voice);
    } else if (component->is_initialized && component->vad_service) {
        // Fall back to energy-based VAD
        result =
            rac_energy_vad_process_audio(component->vad_service, samples, num_samples, &has_voice);
    } else {
        return RAC_ERROR_NOT_INITIALIZED;
    }

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
        RAC_LOG_WARNING("VAD.Component",
                        "Threshold is very low (< 0.002) and may cause false positives");
    }
    if (threshold > 0.1f) {
        RAC_LOG_WARNING("VAD.Component", "Threshold is very high (> 0.1) and may miss speech");
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

    if (component->is_model_loaded) {
        return RAC_LIFECYCLE_STATE_LOADED;
    }

    if (component->is_initialized.load(std::memory_order_acquire)) {
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
    std::lock_guard<std::mutex> lock(component->mtx);
    if (component->is_initialized) {
        out_metrics->total_loads = 1;
        out_metrics->successful_loads = 1;
    }

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_vad_component_get_statistics(rac_handle_t handle,
                                                          float* ambient_level_out,
                                                          float* recent_avg_out,
                                                          float* recent_max_out) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    // Initialise outputs to safe defaults regardless of code path.
    if (ambient_level_out) *ambient_level_out = 0.0f;
    if (recent_avg_out)    *recent_avg_out    = 0.0f;
    if (recent_max_out)    *recent_max_out    = 0.0f;

    auto* component = reinterpret_cast<rac_vad_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // When a model-based VAD is active we cannot surface energy stats; return
    // zeroes (RAC_SUCCESS) so callers don't need to special-case the path.
    if (component->is_model_loaded || !component->vad_service) {
        return RAC_SUCCESS;
    }

    // Delegate to the energy VAD statistics query.
    rac_energy_vad_stats_t stats = {};
    rac_result_t result = rac_energy_vad_get_statistics(component->vad_service, &stats);
    if (result != RAC_SUCCESS) {
        return result;
    }

    if (ambient_level_out) *ambient_level_out = stats.ambient;
    if (recent_avg_out)    *recent_avg_out    = stats.recent_avg;
    if (recent_max_out)    *recent_max_out    = stats.recent_max;

    return RAC_SUCCESS;
}

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

extern "C" rac_result_t rac_vad_component_configure_proto(
    rac_handle_t handle,
    const uint8_t* config_proto_bytes,
    size_t config_proto_size) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!proto_bytes_valid(config_proto_bytes, config_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::VADConfiguration proto;
    if (!proto.ParseFromArray(proto_parse_data(config_proto_bytes, config_proto_size),
                              static_cast<int>(config_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    rac_vad_config_t config = RAC_VAD_CONFIG_DEFAULT;
    config.sample_rate = proto.sample_rate() > 0 ? proto.sample_rate() : RAC_VAD_DEFAULT_SAMPLE_RATE;
    config.frame_length =
        proto.frame_length_ms() > 0
            ? static_cast<float>(proto.frame_length_ms()) / 1000.0f
            : RAC_VAD_DEFAULT_FRAME_LENGTH;
    config.energy_threshold =
        proto.threshold() > 0.0f ? proto.threshold() : RAC_VAD_DEFAULT_ENERGY_THRESHOLD;
    config.enable_auto_calibration = proto.enable_auto_calibration() ? RAC_TRUE : RAC_FALSE;
    return rac_vad_component_configure(handle, &config);
#endif
}

extern "C" rac_result_t rac_vad_component_process_proto(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    const uint8_t* options_proto_bytes,
    size_t options_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)samples;
    (void)num_samples;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle || !samples || num_samples == 0) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "VAD process proto requires handle and samples");
    }
    if (!proto_bytes_valid(options_proto_bytes, options_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "VADOptions bytes are invalid");
    }

    runanywhere::v1::VADOptions options;
    if (!options.ParseFromArray(proto_parse_data(options_proto_bytes, options_proto_size),
                                static_cast<int>(options_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VADOptions");
    }

    int32_t sample_rate = RAC_VAD_DEFAULT_SAMPLE_RATE;
    float threshold = RAC_VAD_DEFAULT_ENERGY_THRESHOLD;
    {
        auto* component = reinterpret_cast<rac_vad_component*>(handle);
        std::lock_guard<std::mutex> lock(component->mtx);
        sample_rate = component->config.sample_rate > 0 ? component->config.sample_rate
                                                        : RAC_VAD_DEFAULT_SAMPLE_RATE;
        threshold = component->config.energy_threshold > 0.0f ? component->config.energy_threshold
                                                              : RAC_VAD_DEFAULT_ENERGY_THRESHOLD;
    }

    const float original_threshold = threshold;
    const bool has_override = options.threshold() > 0.0f;
    if (has_override) {
        (void)rac_vad_component_set_energy_threshold(handle, options.threshold());
        threshold = options.threshold();
    }

    rac_bool_t is_speech = RAC_FALSE;
    rac_result_t rc = rac_vad_component_process(handle, samples, num_samples, &is_speech);
    if (has_override) {
        (void)rac_vad_component_set_energy_threshold(handle, original_threshold);
    }
    if (rc != RAC_SUCCESS) {
        publish_vad_pipeline_event(false, 0.0f, 0.0f, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "VAD processing failed", "vad", "process",
                                            RAC_TRUE);
        return rac_proto_buffer_set_error(out_result, rc, "VAD processing failed");
    }

    const float energy = compute_rms_energy(samples, num_samples);
    const float confidence =
        threshold > 0.0f ? std::min(1.0f, energy / threshold) : (is_speech ? 1.0f : 0.0f);
    const int32_t duration_ms =
        static_cast<int32_t>((static_cast<double>(num_samples) /
                              static_cast<double>(sample_rate > 0 ? sample_rate
                                                                  : RAC_VAD_DEFAULT_SAMPLE_RATE)) *
                             1000.0);

    runanywhere::v1::VADResult result;
    result.set_is_speech(is_speech == RAC_TRUE);
    result.set_confidence(confidence);
    result.set_energy(energy);
    result.set_duration_ms(duration_ms);
    publish_vad_pipeline_event(is_speech == RAC_TRUE, confidence, energy, duration_ms);
    return copy_proto_message(result, out_result);
#endif
}

extern "C" rac_result_t rac_vad_component_get_statistics_proto(
    rac_handle_t handle,
    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                          "VAD handle is required");
    }

    float ambient = 0.0f;
    float recent_avg = 0.0f;
    float recent_max = 0.0f;
    rac_result_t rc =
        rac_vad_component_get_statistics(handle, &ambient, &recent_avg, &recent_max);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD statistics query failed");
    }

    runanywhere::v1::VADStatistics stats;
    stats.set_current_energy(recent_avg);
    stats.set_current_threshold(rac_vad_component_get_energy_threshold(handle));
    stats.set_ambient_level(ambient);
    stats.set_recent_avg(recent_avg);
    stats.set_recent_max(recent_max);
    return copy_proto_message(stats, out_result);
#endif
}

extern "C" rac_result_t rac_vad_component_set_activity_proto_callback(
    rac_handle_t handle,
    rac_vad_proto_activity_callback_fn callback,
    void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (!callback) {
        clear_proto_activity_slot(handle);
        return rac_vad_component_set_activity_callback(handle, nullptr, nullptr);
    }

    {
        std::lock_guard<std::mutex> lock(proto_activity_mutex());
        proto_activity_slots()[handle] = ProtoActivitySlot{callback, user_data};
    }
    return rac_vad_component_set_activity_callback(handle, proto_activity_trampoline, handle);
#endif
}
