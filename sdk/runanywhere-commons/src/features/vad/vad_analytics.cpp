/**
 * @file vad_analytics.cpp
 * @brief VAD analytics service implementation
 *
 * 1:1 port of Swift's VADAnalyticsService.swift
 * Swift Source: Sources/RunAnywhere/Features/VAD/Analytics/VADAnalyticsService.swift
 */

#include <chrono>
#include <cstdlib>
#include <mutex>
#include <new>

#include "rac/core/rac_logger.h"
#include "rac/features/vad/rac_vad_analytics.h"

// =============================================================================
// INTERNAL UTILITIES
// =============================================================================

namespace {

int64_t get_current_time_ms() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

}  // namespace

// =============================================================================
// VAD ANALYTICS SERVICE IMPLEMENTATION
// =============================================================================

struct rac_vad_analytics_s {
    std::mutex mutex;

    // Current framework
    rac_inference_framework_t current_framework;

    // Speech segment tracking
    int64_t speech_start_time_ms;
    bool has_speech_start;

    // Metrics
    int32_t total_speech_segments;
    double total_speech_duration_ms;
    int64_t start_time_ms;
    int64_t last_event_time_ms;
    bool has_last_event_time;

    rac_vad_analytics_s()
        : current_framework(RAC_FRAMEWORK_BUILTIN),
          speech_start_time_ms(0),
          has_speech_start(false),
          total_speech_segments(0),
          total_speech_duration_ms(0),
          start_time_ms(get_current_time_ms()),
          last_event_time_ms(0),
          has_last_event_time(false) {}
};

// =============================================================================
// C API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_vad_analytics_create(rac_vad_analytics_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    *out_handle = new (std::nothrow) rac_vad_analytics_s();
    if (!*out_handle) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    log_info("VAD.Analytics", "VAD analytics service created");
    return RAC_SUCCESS;
}

void rac_vad_analytics_destroy(rac_vad_analytics_handle_t handle) {
    if (handle) {
        delete handle;
        log_info("VAD.Analytics", "VAD analytics service destroyed");
    }
}

rac_result_t rac_vad_analytics_track_initialized(rac_vad_analytics_handle_t handle,
                                                 rac_inference_framework_t framework) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->current_framework = framework;
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD initialized with framework: %d", framework);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_initialization_failed(rac_vad_analytics_handle_t handle,
                                                           rac_result_t error_code,
                                                           const char* error_message,
                                                           rac_inference_framework_t framework) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->current_framework = framework;
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("VAD.Analytics", "VAD initialization failed: %d - %s", error_code,
              error_message ? error_message : "");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_cleaned_up(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD cleaned up");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_started(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD started");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_stopped(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD stopped");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_speech_start(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    int64_t now = get_current_time_ms();
    handle->speech_start_time_ms = now;
    handle->has_speech_start = true;
    handle->last_event_time_ms = now;
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "Speech started");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_speech_end(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->has_speech_start) {
        return RAC_SUCCESS;  // No speech start to end
    }

    int64_t end_time_ms = get_current_time_ms();
    double duration_ms = static_cast<double>(end_time_ms - handle->speech_start_time_ms);

    handle->has_speech_start = false;
    handle->total_speech_segments++;
    handle->total_speech_duration_ms += duration_ms;
    handle->last_event_time_ms = end_time_ms;
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "Speech ended: %.1fms", duration_ms);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_paused(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD paused");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_resumed(rac_vad_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "VAD resumed");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_model_load_started(rac_vad_analytics_handle_t handle,
                                                        const char* model_id,
                                                        int64_t model_size_bytes,
                                                        rac_inference_framework_t framework) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->current_framework = framework;
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "Model load started: %s, size: %lld", model_id, model_size_bytes);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_model_load_completed(rac_vad_analytics_handle_t handle,
                                                          const char* model_id, double duration_ms,
                                                          int64_t model_size_bytes) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "Model load completed: %s, duration: %.1fms, size: %lld", model_id,
              duration_ms, model_size_bytes);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_model_load_failed(rac_vad_analytics_handle_t handle,
                                                       const char* model_id,
                                                       rac_result_t error_code,
                                                       const char* error_message) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("VAD.Analytics", "Model load failed: %s, error: %d - %s", model_id, error_code,
              error_message ? error_message : "");
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_track_model_unloaded(rac_vad_analytics_handle_t handle,
                                                    const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_debug("VAD.Analytics", "Model unloaded: %s", model_id);
    return RAC_SUCCESS;
}

rac_result_t rac_vad_analytics_get_metrics(rac_vad_analytics_handle_t handle,
                                           rac_vad_metrics_t* out_metrics) {
    if (!handle || !out_metrics) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    out_metrics->total_events = handle->total_speech_segments;
    out_metrics->start_time_ms = handle->start_time_ms;
    out_metrics->last_event_time_ms = handle->has_last_event_time ? handle->last_event_time_ms : 0;
    out_metrics->total_speech_segments = handle->total_speech_segments;
    out_metrics->total_speech_duration_ms = handle->total_speech_duration_ms;

    // Average speech duration (-1 if no segments, matching Swift)
    out_metrics->average_speech_duration_ms =
        handle->total_speech_segments > 0
            ? handle->total_speech_duration_ms / static_cast<double>(handle->total_speech_segments)
            : -1;

    out_metrics->framework = handle->current_framework;

    return RAC_SUCCESS;
}

}  // extern "C"
