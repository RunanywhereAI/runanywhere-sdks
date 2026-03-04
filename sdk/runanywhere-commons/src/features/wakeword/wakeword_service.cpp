/**
 * @file wakeword_service.cpp
 * @brief Wake Word Service Implementation
 *
 * Implements the wake word detection service with:
 * - Multiple model support
 * - VAD pre-filtering (Silero)
 * - Configurable thresholds
 * - Callback-based detection events
 */

#include "rac/features/wakeword/rac_wakeword_service.h"
#include "rac/core/rac_logger.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace rac {
namespace wakeword {

// =============================================================================
// INTERNAL TYPES
// =============================================================================

struct LoadedModel {
    std::string model_id;
    std::string wake_word;
    std::string model_path;
    float threshold_override = -1.0f;
    bool is_loaded = false;
};

struct WakewordService {
    // Configuration
    rac_wakeword_config_t config = RAC_WAKEWORD_CONFIG_DEFAULT;

    // State
    std::atomic<bool> initialized{false};
    std::atomic<bool> listening{false};
    std::atomic<bool> paused{false};

    // Models
    std::vector<LoadedModel> models;
    std::string vad_model_path;
    bool vad_loaded = false;

    // Callbacks
    rac_wakeword_callback_fn detection_callback = nullptr;
    void* detection_user_data = nullptr;
    rac_wakeword_vad_callback_fn vad_callback = nullptr;
    void* vad_user_data = nullptr;

    // Statistics
    int64_t total_detections = 0;
    int64_t stream_start_time = 0;
    int64_t last_detection_time = 0;

    // Audio buffer for accumulating samples
    std::vector<float> audio_buffer;
    size_t samples_per_frame = 0;

    // Thread safety
    mutable std::mutex mutex;

    // Backend handle (ONNX)
    rac_handle_t backend_handle = nullptr;
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static int64_t get_timestamp_ms() {
    auto now = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()
    ).count();
}

static WakewordService* get_service(rac_handle_t handle) {
    return static_cast<WakewordService*>(handle);
}

static bool is_valid_handle(rac_handle_t handle) {
    return handle != nullptr;
}

// =============================================================================
// SERVICE LIFECYCLE
// =============================================================================

extern "C" {

RAC_API rac_result_t rac_wakeword_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = new (std::nothrow) WakewordService();
    if (!service) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    *out_handle = static_cast<rac_handle_t>(service);
    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_initialize(rac_handle_t handle,
                                              const rac_wakeword_config_t* config) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    if (service->initialized) {
        return RAC_SUCCESS;  // Already initialized
    }

    // Apply configuration
    if (config) {
        service->config = *config;
    }

    // Calculate samples per frame
    service->samples_per_frame =
        (service->config.sample_rate * service->config.frame_length_ms) / 1000;

    // Reserve audio buffer
    service->audio_buffer.reserve(service->samples_per_frame * 2);

    service->initialized = true;
    service->stream_start_time = get_timestamp_ms();

    RAC_LOG_INFO("WakeWord", "Service initialized (sample_rate=%d, frame=%dms)",
                 service->config.sample_rate, service->config.frame_length_ms);

    return RAC_SUCCESS;
}

RAC_API void rac_wakeword_destroy(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return;
    }

    auto* service = get_service(handle);

    // Stop if running
    if (service->listening) {
        rac_wakeword_stop(handle);
    }

    // TODO: Destroy backend handle when implemented
    // if (service->backend_handle) {
    //     rac_wakeword_onnx_destroy(service->backend_handle);
    // }

    delete service;
}

// =============================================================================
// MODEL MANAGEMENT
// =============================================================================

RAC_API rac_result_t rac_wakeword_load_model(rac_handle_t handle,
                                              const char* model_path,
                                              const char* model_id,
                                              const char* wake_word) {
    if (!is_valid_handle(handle) || !model_path || !model_id || !wake_word) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    if (!service->initialized) {
        return RAC_ERROR_WAKEWORD_NOT_INITIALIZED;
    }

    // Check max models
    if (service->models.size() >= RAC_WAKEWORD_MAX_MODELS) {
        return RAC_ERROR_WAKEWORD_MAX_MODELS;
    }

    // Check for duplicate model_id
    for (const auto& model : service->models) {
        if (model.model_id == model_id) {
            RAC_LOG_WARNING("WakeWord", "Model already loaded: %s", model_id);
            return RAC_SUCCESS;
        }
    }

    // Add model entry
    LoadedModel model;
    model.model_id = model_id;
    model.wake_word = wake_word;
    model.model_path = model_path;
    model.is_loaded = true;  // TODO: Actually load via backend

    service->models.push_back(model);

    RAC_LOG_INFO("WakeWord", "Loaded model: %s ('%s')", model_id, wake_word);

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_load_vad(rac_handle_t handle,
                                            const char* vad_model_path) {
    if (!is_valid_handle(handle) || !vad_model_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    if (!service->initialized) {
        return RAC_ERROR_WAKEWORD_NOT_INITIALIZED;
    }

    service->vad_model_path = vad_model_path;
    service->vad_loaded = true;  // TODO: Actually load via backend

    RAC_LOG_INFO("WakeWord", "Loaded VAD model: %s", vad_model_path);

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_unload_model(rac_handle_t handle,
                                                const char* model_id) {
    if (!is_valid_handle(handle) || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    auto it = std::find_if(service->models.begin(), service->models.end(),
                           [model_id](const LoadedModel& m) {
                               return m.model_id == model_id;
                           });

    if (it == service->models.end()) {
        return RAC_ERROR_WAKEWORD_MODEL_NOT_FOUND;
    }

    service->models.erase(it);
    RAC_LOG_INFO("WakeWord", "Unloaded model: %s", model_id);

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_unload_all(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->models.clear();
    RAC_LOG_INFO("WakeWord", "Unloaded all models");

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_get_models(rac_handle_t handle,
                                              const rac_wakeword_model_info_t** out_models,
                                              int32_t* out_count) {
    if (!is_valid_handle(handle) || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    *out_count = static_cast<int32_t>(service->models.size());

    // Note: For a real implementation, we'd need to maintain a stable
    // array of rac_wakeword_model_info_t structs
    if (out_models) {
        *out_models = nullptr;  // TODO: Implement proper model info array
    }

    return RAC_SUCCESS;
}

// =============================================================================
// CALLBACKS
// =============================================================================

RAC_API rac_result_t rac_wakeword_set_callback(rac_handle_t handle,
                                                rac_wakeword_callback_fn callback,
                                                void* user_data) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->detection_callback = callback;
    service->detection_user_data = user_data;

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_set_vad_callback(rac_handle_t handle,
                                                    rac_wakeword_vad_callback_fn callback,
                                                    void* user_data) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->vad_callback = callback;
    service->vad_user_data = user_data;

    return RAC_SUCCESS;
}

// =============================================================================
// DETECTION CONTROL
// =============================================================================

RAC_API rac_result_t rac_wakeword_start(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    if (!service->initialized) {
        return RAC_ERROR_WAKEWORD_NOT_INITIALIZED;
    }

    if (service->listening) {
        return RAC_ERROR_WAKEWORD_ALREADY_LISTENING;
    }

    service->listening = true;
    service->paused = false;
    service->stream_start_time = get_timestamp_ms();
    service->audio_buffer.clear();

    RAC_LOG_INFO("WakeWord", "Started listening");

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_stop(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    if (!service->listening) {
        return RAC_ERROR_WAKEWORD_NOT_LISTENING;
    }

    service->listening = false;
    service->paused = false;
    service->audio_buffer.clear();

    RAC_LOG_INFO("WakeWord", "Stopped listening");

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_pause(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    service->paused = true;

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_resume(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    service->paused = false;

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_reset(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->audio_buffer.clear();
    service->last_detection_time = 0;

    // TODO: Reset backend state

    return RAC_SUCCESS;
}

// =============================================================================
// AUDIO PROCESSING
// =============================================================================

RAC_API rac_result_t rac_wakeword_process(rac_handle_t handle,
                                           const float* samples,
                                           size_t num_samples,
                                           rac_wakeword_frame_result_t* out_result) {
    if (!is_valid_handle(handle) || !samples || num_samples == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);

    // Early exit if not listening or paused
    if (!service->listening || service->paused) {
        if (out_result) {
            out_result->detected = RAC_FALSE;
            out_result->keyword_index = -1;
            out_result->confidence = 0.0f;
        }
        return RAC_SUCCESS;
    }

    std::unique_lock<std::mutex> lock(service->mutex);

    // Accumulate samples
    service->audio_buffer.insert(service->audio_buffer.end(),
                                  samples, samples + num_samples);

    // Initialize result
    if (out_result) {
        out_result->detected = RAC_FALSE;
        out_result->keyword_index = -1;
        out_result->confidence = 0.0f;
        out_result->vad_probability = 0.0f;
        out_result->vad_is_speech = RAC_FALSE;
    }

    // Process complete frames
    while (service->audio_buffer.size() >= service->samples_per_frame) {
        // Extract frame
        std::vector<float> frame(
            service->audio_buffer.begin(),
            service->audio_buffer.begin() + service->samples_per_frame
        );

        // Remove processed samples
        service->audio_buffer.erase(
            service->audio_buffer.begin(),
            service->audio_buffer.begin() + service->samples_per_frame
        );

        // TODO: Process through ONNX backend
        // For now, simulate with placeholder
        bool detected = false;
        int32_t keyword_index = -1;
        float confidence = 0.0f;
        bool vad_speech = true;  // Assume speech if no VAD
        float vad_prob = 1.0f;

        // VAD pre-filtering (would call backend)
        if (service->config.use_vad_filter && service->vad_loaded) {
            // TODO: Run VAD inference
            // vad_speech = rac_wakeword_onnx_vad_process(...)
        }

        // Copy VAD callback under lock to invoke outside lock (avoid deadlock)
        auto vad_cb = service->vad_callback;
        auto vad_ud = service->vad_user_data;

        // Only run wake word detection if VAD detects speech
        if (!service->config.use_vad_filter || vad_speech) {
            // TODO: Run wake word inference for each model
            // detected = rac_wakeword_onnx_process(...)
        }

        // Update result
        if (out_result) {
            out_result->vad_probability = vad_prob;
            out_result->vad_is_speech = vad_speech ? RAC_TRUE : RAC_FALSE;
        }

        // Prepare detection callback data under lock (if detection occurred)
        rac_wakeword_callback_fn det_cb = nullptr;
        void* det_ud = nullptr;
        rac_wakeword_event_t event = {};
        bool should_invoke_detection = false;

        if (detected && keyword_index >= 0) {
            int64_t now = get_timestamp_ms();
            int64_t elapsed = now - service->last_detection_time;

            if (elapsed >= service->config.min_detection_interval_ms) {
                service->last_detection_time = now;
                service->total_detections++;

                if (out_result) {
                    out_result->detected = RAC_TRUE;
                    out_result->keyword_index = keyword_index;
                    out_result->confidence = confidence;
                }

                if (service->detection_callback && keyword_index < (int32_t)service->models.size()) {
                    det_cb = service->detection_callback;
                    det_ud = service->detection_user_data;
                    event.keyword_index = keyword_index;
                    event.keyword_name = service->models[keyword_index].wake_word.c_str();
                    event.model_id = service->models[keyword_index].model_id.c_str();
                    event.confidence = confidence;
                    event.timestamp_ms = now - service->stream_start_time;
                    event.duration_ms = service->config.frame_length_ms;
                    should_invoke_detection = true;
                }
            }
        }

        // Release lock before invoking callbacks to avoid deadlock
        lock.unlock();

        // Invoke VAD callback outside lock
        if (vad_cb) {
            vad_cb(vad_speech ? RAC_TRUE : RAC_FALSE, vad_prob, vad_ud);
        }

        // Invoke detection callback outside lock
        if (should_invoke_detection && det_cb) {
            det_cb(&event, det_ud);
        }

        // Re-acquire lock for next iteration
        lock.lock();

        // If we had a detection, only report first per process call
        if (should_invoke_detection) {
            break;
        }
    }

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_process_int16(rac_handle_t handle,
                                                 const int16_t* samples,
                                                 size_t num_samples,
                                                 rac_wakeword_frame_result_t* out_result) {
    if (!samples || num_samples == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Convert int16 to float
    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;
    }

    return rac_wakeword_process(handle, float_samples.data(), num_samples, out_result);
}

// =============================================================================
// CONFIGURATION
// =============================================================================

RAC_API rac_result_t rac_wakeword_set_threshold(rac_handle_t handle, float threshold) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    if (threshold < 0.0f || threshold > 1.0f) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->config.threshold = threshold;

    return RAC_SUCCESS;
}

RAC_API rac_result_t rac_wakeword_set_model_threshold(rac_handle_t handle,
                                                       const char* model_id,
                                                       float threshold) {
    if (!is_valid_handle(handle) || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (threshold < 0.0f || threshold > 1.0f) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    for (auto& model : service->models) {
        if (model.model_id == model_id) {
            model.threshold_override = threshold;
            return RAC_SUCCESS;
        }
    }

    return RAC_ERROR_WAKEWORD_MODEL_NOT_FOUND;
}

RAC_API rac_result_t rac_wakeword_set_vad_enabled(rac_handle_t handle, rac_bool_t enabled) {
    if (!is_valid_handle(handle)) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    service->config.use_vad_filter = enabled;

    return RAC_SUCCESS;
}

// =============================================================================
// STATUS
// =============================================================================

RAC_API rac_result_t rac_wakeword_get_info(rac_handle_t handle,
                                            rac_wakeword_info_t* out_info) {
    if (!is_valid_handle(handle) || !out_info) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* service = get_service(handle);
    std::lock_guard<std::mutex> lock(service->mutex);

    out_info->is_ready = service->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->is_listening = service->listening ? RAC_TRUE : RAC_FALSE;
    out_info->vad_enabled = service->config.use_vad_filter;
    out_info->num_models = static_cast<int32_t>(service->models.size());
    out_info->models = nullptr;  // TODO: Proper model info array
    out_info->total_detections = service->total_detections;
    out_info->sample_rate = service->config.sample_rate;
    out_info->threshold = service->config.threshold;

    return RAC_SUCCESS;
}

RAC_API rac_bool_t rac_wakeword_is_ready(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_FALSE;
    }
    return get_service(handle)->initialized ? RAC_TRUE : RAC_FALSE;
}

RAC_API rac_bool_t rac_wakeword_is_listening(rac_handle_t handle) {
    if (!is_valid_handle(handle)) {
        return RAC_FALSE;
    }
    return get_service(handle)->listening ? RAC_TRUE : RAC_FALSE;
}

} // extern "C"

} // namespace wakeword
} // namespace rac
