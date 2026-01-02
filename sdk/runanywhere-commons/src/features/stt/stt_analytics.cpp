/**
 * @file stt_analytics.cpp
 * @brief STT analytics service implementation
 *
 * 1:1 port of Swift's STTAnalyticsService.swift
 * Swift Source: Sources/RunAnywhere/Features/STT/Analytics/STTAnalyticsService.swift
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <random>
#include <sstream>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_analytics.h"

// =============================================================================
// INTERNAL TYPES - Mirrors Swift's TranscriptionTracker
// =============================================================================

namespace {

struct TranscriptionTracker {
    int64_t start_time_ms;
    std::string model_id;
    double audio_length_ms;
    int32_t audio_size_bytes;
    std::string language;
    bool is_streaming;
    int32_t sample_rate;
    rac_inference_framework_t framework;
};

int64_t get_current_time_ms() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

std::string generate_uuid() {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis(0, 15);

    std::stringstream ss;
    ss << std::hex;

    for (int i = 0; i < 8; i++)
        ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 4; i++)
        ss << dis(gen);
    ss << "-4";
    for (int i = 0; i < 3; i++)
        ss << dis(gen);
    ss << "-";
    ss << (8 + dis(gen) % 4);
    for (int i = 0; i < 3; i++)
        ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 12; i++)
        ss << dis(gen);

    return ss.str();
}

}  // namespace

// =============================================================================
// STT ANALYTICS SERVICE IMPLEMENTATION
// =============================================================================

struct rac_stt_analytics_s {
    std::mutex mutex;
    std::map<std::string, TranscriptionTracker> active_transcriptions;

    // Metrics (mirrors Swift)
    int32_t transcription_count;
    float total_confidence;
    double total_latency_ms;
    double total_audio_processed_ms;
    double total_real_time_factor;
    int64_t start_time_ms;
    int64_t last_event_time_ms;
    bool has_last_event_time;

    rac_stt_analytics_s()
        : transcription_count(0),
          total_confidence(0.0f),
          total_latency_ms(0),
          total_audio_processed_ms(0),
          total_real_time_factor(0),
          start_time_ms(get_current_time_ms()),
          last_event_time_ms(0),
          has_last_event_time(false) {}
};

// =============================================================================
// C API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_stt_analytics_create(rac_stt_analytics_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    try {
        *out_handle = new rac_stt_analytics_s();
        log_info("STT.Analytics", "STT analytics service created");
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

void rac_stt_analytics_destroy(rac_stt_analytics_handle_t handle) {
    if (handle) {
        delete handle;
        log_info("STT.Analytics", "STT analytics service destroyed");
    }
}

rac_result_t rac_stt_analytics_start_transcription(rac_stt_analytics_handle_t handle,
                                                   const char* model_id, double audio_length_ms,
                                                   int32_t audio_size_bytes, const char* language,
                                                   rac_bool_t is_streaming, int32_t sample_rate,
                                                   rac_inference_framework_t framework,
                                                   char** out_transcription_id) {
    if (!handle || !model_id || !language || !out_transcription_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string id = generate_uuid();

    TranscriptionTracker tracker;
    tracker.start_time_ms = get_current_time_ms();
    tracker.model_id = model_id;
    tracker.audio_length_ms = audio_length_ms;
    tracker.audio_size_bytes = audio_size_bytes;
    tracker.language = language;
    tracker.is_streaming = is_streaming == RAC_TRUE;
    tracker.sample_rate = sample_rate;
    tracker.framework = framework;

    handle->active_transcriptions[id] = tracker;

    *out_transcription_id = static_cast<char*>(malloc(id.size() + 1));
    if (!*out_transcription_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    strcpy(*out_transcription_id, id.c_str());

    log_debug("STT.Analytics", "Transcription started: %s, model: %s, audio: %.1fms, %d bytes",
              id.c_str(), model_id, audio_length_ms, audio_size_bytes);

    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_track_partial_transcript(rac_stt_analytics_handle_t handle,
                                                        const char* text) {
    if (!handle || !text) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Event would be published here in full implementation
    log_debug("STT.Analytics", "Partial transcript received");
    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_track_final_transcript(rac_stt_analytics_handle_t handle,
                                                      const char* text, float confidence) {
    if (!handle || !text) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Event would be published here in full implementation
    log_debug("STT.Analytics", "Final transcript: confidence=%.2f", confidence);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_complete_transcription(rac_stt_analytics_handle_t handle,
                                                      const char* transcription_id,
                                                      const char* text, float confidence) {
    if (!handle || !transcription_id || !text) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_transcriptions.find(transcription_id);
    if (it == handle->active_transcriptions.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    TranscriptionTracker tracker = it->second;
    handle->active_transcriptions.erase(it);

    int64_t end_time_ms = get_current_time_ms();
    double processing_time_ms = static_cast<double>(end_time_ms - tracker.start_time_ms);

    // Calculate real-time factor (RTF): processing time / audio length
    double real_time_factor =
        tracker.audio_length_ms > 0 ? processing_time_ms / tracker.audio_length_ms : 0;

    // Update metrics
    handle->transcription_count++;
    handle->total_confidence += confidence;
    handle->total_latency_ms += processing_time_ms;
    handle->total_audio_processed_ms += tracker.audio_length_ms;
    handle->total_real_time_factor += real_time_factor;
    handle->last_event_time_ms = end_time_ms;
    handle->has_last_event_time = true;

    log_debug("STT.Analytics", "Transcription completed: %s, model: %s, RTF: %.3f",
              transcription_id, tracker.model_id.c_str(), real_time_factor);

    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_track_transcription_failed(rac_stt_analytics_handle_t handle,
                                                          const char* transcription_id,
                                                          rac_result_t error_code,
                                                          const char* error_message) {
    if (!handle || !transcription_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->active_transcriptions.erase(transcription_id);
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("STT.Analytics", "Transcription failed %s: %d - %s", transcription_id, error_code,
              error_message ? error_message : "");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_track_language_detection(rac_stt_analytics_handle_t handle,
                                                        const char* language, float confidence) {
    if (!handle || !language) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    log_debug("STT.Analytics", "Language detected: %s (%.2f)", language, confidence);
    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_track_error(rac_stt_analytics_handle_t handle,
                                           rac_result_t error_code, const char* error_message,
                                           const char* operation, const char* model_id,
                                           const char* transcription_id) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("STT.Analytics", "STT error in %s: %d - %s (model: %s, trans: %s)",
              operation ? operation : "unknown", error_code, error_message ? error_message : "",
              model_id ? model_id : "none", transcription_id ? transcription_id : "none");

    return RAC_SUCCESS;
}

rac_result_t rac_stt_analytics_get_metrics(rac_stt_analytics_handle_t handle,
                                           rac_stt_metrics_t* out_metrics) {
    if (!handle || !out_metrics) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    out_metrics->total_events = handle->transcription_count;
    out_metrics->start_time_ms = handle->start_time_ms;
    out_metrics->last_event_time_ms = handle->has_last_event_time ? handle->last_event_time_ms : 0;
    out_metrics->total_transcriptions = handle->transcription_count;

    out_metrics->average_confidence =
        handle->transcription_count > 0
            ? handle->total_confidence / static_cast<float>(handle->transcription_count)
            : 0;

    out_metrics->average_latency_ms =
        handle->transcription_count > 0
            ? handle->total_latency_ms / static_cast<double>(handle->transcription_count)
            : 0;

    out_metrics->average_real_time_factor =
        handle->transcription_count > 0
            ? handle->total_real_time_factor / static_cast<double>(handle->transcription_count)
            : 0;

    out_metrics->total_audio_processed_ms = handle->total_audio_processed_ms;

    return RAC_SUCCESS;
}

}  // extern "C"
