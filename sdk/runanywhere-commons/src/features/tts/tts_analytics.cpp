/**
 * @file tts_analytics.cpp
 * @brief TTS analytics service implementation
 *
 * 1:1 port of Swift's TTSAnalyticsService.swift
 * Swift Source: Sources/RunAnywhere/Features/TTS/Analytics/TTSAnalyticsService.swift
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
#include "rac/features/tts/rac_tts_analytics.h"

// =============================================================================
// INTERNAL TYPES - Mirrors Swift's SynthesisTracker
// =============================================================================

namespace {

struct SynthesisTracker {
    int64_t start_time_ms;
    std::string model_id;
    int32_t character_count;
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
// TTS ANALYTICS SERVICE IMPLEMENTATION
// =============================================================================

struct rac_tts_analytics_s {
    std::mutex mutex;
    std::map<std::string, SynthesisTracker> active_syntheses;

    // Metrics (mirrors Swift)
    int32_t synthesis_count;
    int32_t total_characters;
    double total_processing_time_ms;
    double total_audio_duration_ms;
    int64_t total_audio_size_bytes;
    double total_characters_per_second;
    int64_t start_time_ms;
    int64_t last_event_time_ms;
    bool has_last_event_time;

    rac_tts_analytics_s()
        : synthesis_count(0),
          total_characters(0),
          total_processing_time_ms(0),
          total_audio_duration_ms(0),
          total_audio_size_bytes(0),
          total_characters_per_second(0),
          start_time_ms(get_current_time_ms()),
          last_event_time_ms(0),
          has_last_event_time(false) {}
};

// =============================================================================
// C API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_tts_analytics_create(rac_tts_analytics_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    try {
        *out_handle = new rac_tts_analytics_s();
        log_info("TTS.Analytics", "TTS analytics service created");
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

void rac_tts_analytics_destroy(rac_tts_analytics_handle_t handle) {
    if (handle) {
        delete handle;
        log_info("TTS.Analytics", "TTS analytics service destroyed");
    }
}

rac_result_t rac_tts_analytics_start_synthesis(rac_tts_analytics_handle_t handle, const char* text,
                                               const char* voice, int32_t sample_rate,
                                               rac_inference_framework_t framework,
                                               char** out_synthesis_id) {
    if (!handle || !text || !voice || !out_synthesis_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string id = generate_uuid();
    int32_t character_count = static_cast<int32_t>(strlen(text));

    SynthesisTracker tracker;
    tracker.start_time_ms = get_current_time_ms();
    tracker.model_id = voice;
    tracker.character_count = character_count;
    tracker.sample_rate = sample_rate;
    tracker.framework = framework;

    handle->active_syntheses[id] = tracker;

    *out_synthesis_id = static_cast<char*>(malloc(id.size() + 1));
    if (!*out_synthesis_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    strcpy(*out_synthesis_id, id.c_str());

    log_debug("TTS.Analytics", "Synthesis started: %s, voice: %s, %d characters", id.c_str(), voice,
              character_count);

    return RAC_SUCCESS;
}

rac_result_t rac_tts_analytics_track_synthesis_chunk(rac_tts_analytics_handle_t handle,
                                                     const char* synthesis_id, int32_t chunk_size) {
    if (!handle || !synthesis_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Event would be published here in full implementation
    log_debug("TTS.Analytics", "Synthesis chunk: %s, size: %d", synthesis_id, chunk_size);
    return RAC_SUCCESS;
}

rac_result_t rac_tts_analytics_complete_synthesis(rac_tts_analytics_handle_t handle,
                                                  const char* synthesis_id,
                                                  double audio_duration_ms,
                                                  int32_t audio_size_bytes) {
    if (!handle || !synthesis_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_syntheses.find(synthesis_id);
    if (it == handle->active_syntheses.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    SynthesisTracker tracker = it->second;
    handle->active_syntheses.erase(it);

    int64_t end_time_ms = get_current_time_ms();
    double processing_time_ms = static_cast<double>(end_time_ms - tracker.start_time_ms);
    int32_t character_count = tracker.character_count;

    // Calculate characters per second
    double chars_per_second = processing_time_ms > 0 ? static_cast<double>(character_count) /
                                                           (processing_time_ms / 1000.0)
                                                     : 0;

    // Update metrics
    handle->synthesis_count++;
    handle->total_characters += character_count;
    handle->total_processing_time_ms += processing_time_ms;
    handle->total_audio_duration_ms += audio_duration_ms;
    handle->total_audio_size_bytes += audio_size_bytes;
    handle->total_characters_per_second += chars_per_second;
    handle->last_event_time_ms = end_time_ms;
    handle->has_last_event_time = true;

    log_debug("TTS.Analytics", "Synthesis completed: %s, voice: %s, audio: %.1fms, %d bytes",
              synthesis_id, tracker.model_id.c_str(), audio_duration_ms, audio_size_bytes);

    return RAC_SUCCESS;
}

rac_result_t rac_tts_analytics_track_synthesis_failed(rac_tts_analytics_handle_t handle,
                                                      const char* synthesis_id,
                                                      rac_result_t error_code,
                                                      const char* error_message) {
    if (!handle || !synthesis_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->active_syntheses.erase(synthesis_id);
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("TTS.Analytics", "Synthesis failed %s: %d - %s", synthesis_id, error_code,
              error_message ? error_message : "");

    return RAC_SUCCESS;
}

rac_result_t rac_tts_analytics_track_error(rac_tts_analytics_handle_t handle,
                                           rac_result_t error_code, const char* error_message,
                                           const char* operation, const char* model_id,
                                           const char* synthesis_id) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("TTS.Analytics", "TTS error in %s: %d - %s (model: %s, syn: %s)",
              operation ? operation : "unknown", error_code, error_message ? error_message : "",
              model_id ? model_id : "none", synthesis_id ? synthesis_id : "none");

    return RAC_SUCCESS;
}

rac_result_t rac_tts_analytics_get_metrics(rac_tts_analytics_handle_t handle,
                                           rac_tts_metrics_t* out_metrics) {
    if (!handle || !out_metrics) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    out_metrics->total_events = handle->synthesis_count;
    out_metrics->start_time_ms = handle->start_time_ms;
    out_metrics->last_event_time_ms = handle->has_last_event_time ? handle->last_event_time_ms : 0;
    out_metrics->total_syntheses = handle->synthesis_count;

    out_metrics->average_characters_per_second =
        handle->synthesis_count > 0
            ? handle->total_characters_per_second / static_cast<double>(handle->synthesis_count)
            : 0;

    out_metrics->average_processing_time_ms =
        handle->synthesis_count > 0
            ? handle->total_processing_time_ms / static_cast<double>(handle->synthesis_count)
            : 0;

    out_metrics->average_audio_duration_ms =
        handle->synthesis_count > 0
            ? handle->total_audio_duration_ms / static_cast<double>(handle->synthesis_count)
            : 0;

    out_metrics->total_characters_processed = handle->total_characters;
    out_metrics->total_audio_size_bytes = handle->total_audio_size_bytes;

    return RAC_SUCCESS;
}

}  // extern "C"
