/**
 * @file llm_analytics.cpp
 * @brief LLM Generation analytics service implementation
 *
 * 1:1 port of Swift's GenerationAnalyticsService.swift
 * Swift Source: Sources/RunAnywhere/Features/LLM/Analytics/GenerationAnalyticsService.swift
 */

#include "rac/features/llm/rac_llm_analytics.h"
#include "rac/core/rac_log.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <random>
#include <sstream>
#include <string>

// =============================================================================
// INTERNAL TYPES - Mirrors Swift's GenerationTracker
// =============================================================================

namespace {

struct GenerationTracker {
    int64_t start_time_ms;
    bool is_streaming;
    rac_inference_framework_t framework;
    std::string model_id;
    float temperature;
    bool has_temperature;
    int32_t max_tokens;
    bool has_max_tokens;
    int32_t context_length;
    bool has_context_length;
    int64_t first_token_time_ms;
    bool has_first_token_time;
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

    for (int i = 0; i < 8; i++) ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 4; i++) ss << dis(gen);
    ss << "-4";  // Version 4 UUID
    for (int i = 0; i < 3; i++) ss << dis(gen);
    ss << "-";
    ss << (8 + dis(gen) % 4);  // Variant
    for (int i = 0; i < 3; i++) ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 12; i++) ss << dis(gen);

    return ss.str();
}

}  // namespace

// =============================================================================
// LLM ANALYTICS SERVICE IMPLEMENTATION
// =============================================================================

struct rac_llm_analytics_s {
    std::mutex mutex;
    std::map<std::string, GenerationTracker> active_generations;

    // Metrics - separated by mode (mirrors Swift)
    int32_t total_generations;
    int32_t streaming_generations;
    int32_t non_streaming_generations;
    double total_time_to_first_token_ms;
    int32_t streaming_ttft_count;  // Only count TTFT for streaming
    double total_tokens_per_second;
    int32_t total_input_tokens;
    int32_t total_output_tokens;
    int64_t start_time_ms;
    int64_t last_event_time_ms;
    bool has_last_event_time;

    rac_llm_analytics_s()
        : total_generations(0)
        , streaming_generations(0)
        , non_streaming_generations(0)
        , total_time_to_first_token_ms(0)
        , streaming_ttft_count(0)
        , total_tokens_per_second(0)
        , total_input_tokens(0)
        , total_output_tokens(0)
        , start_time_ms(get_current_time_ms())
        , last_event_time_ms(0)
        , has_last_event_time(false) {}
};

// =============================================================================
// C API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_llm_analytics_create(rac_llm_analytics_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    try {
        *out_handle = new rac_llm_analytics_s();
        log_info("LLM.Analytics", "LLM analytics service created");
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

void rac_llm_analytics_destroy(rac_llm_analytics_handle_t handle) {
    if (handle) {
        delete handle;
        log_info("LLM.Analytics", "LLM analytics service destroyed");
    }
}

rac_result_t rac_llm_analytics_start_generation(
    rac_llm_analytics_handle_t handle,
    const char* model_id,
    rac_inference_framework_t framework,
    const float* temperature,
    const int32_t* max_tokens,
    const int32_t* context_length,
    char** out_generation_id
) {
    if (!handle || !model_id || !out_generation_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string id = generate_uuid();

    GenerationTracker tracker;
    tracker.start_time_ms = get_current_time_ms();
    tracker.is_streaming = false;
    tracker.framework = framework;
    tracker.model_id = model_id;
    tracker.has_temperature = temperature != nullptr;
    tracker.temperature = temperature ? *temperature : 0.0f;
    tracker.has_max_tokens = max_tokens != nullptr;
    tracker.max_tokens = max_tokens ? *max_tokens : 0;
    tracker.has_context_length = context_length != nullptr;
    tracker.context_length = context_length ? *context_length : 0;
    tracker.has_first_token_time = false;
    tracker.first_token_time_ms = 0;

    handle->active_generations[id] = tracker;

    // Allocate and copy the ID for the caller
    *out_generation_id = static_cast<char*>(malloc(id.size() + 1));
    if (!*out_generation_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    strcpy(*out_generation_id, id.c_str());

    log_debug("LLM.Analytics", "Non-streaming generation started: %s", id.c_str());
    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_start_streaming_generation(
    rac_llm_analytics_handle_t handle,
    const char* model_id,
    rac_inference_framework_t framework,
    const float* temperature,
    const int32_t* max_tokens,
    const int32_t* context_length,
    char** out_generation_id
) {
    if (!handle || !model_id || !out_generation_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string id = generate_uuid();

    GenerationTracker tracker;
    tracker.start_time_ms = get_current_time_ms();
    tracker.is_streaming = true;
    tracker.framework = framework;
    tracker.model_id = model_id;
    tracker.has_temperature = temperature != nullptr;
    tracker.temperature = temperature ? *temperature : 0.0f;
    tracker.has_max_tokens = max_tokens != nullptr;
    tracker.max_tokens = max_tokens ? *max_tokens : 0;
    tracker.has_context_length = context_length != nullptr;
    tracker.context_length = context_length ? *context_length : 0;
    tracker.has_first_token_time = false;
    tracker.first_token_time_ms = 0;

    handle->active_generations[id] = tracker;

    // Allocate and copy the ID for the caller
    *out_generation_id = static_cast<char*>(malloc(id.size() + 1));
    if (!*out_generation_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    strcpy(*out_generation_id, id.c_str());

    log_debug("LLM.Analytics", "Streaming generation started: %s", id.c_str());
    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_track_first_token(
    rac_llm_analytics_handle_t handle,
    const char* generation_id
) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    GenerationTracker& tracker = it->second;

    // TTFT is only tracked for streaming generations
    if (!tracker.is_streaming) {
        return RAC_SUCCESS;  // Silent ignore for non-streaming
    }

    // Only record if not already recorded
    if (tracker.has_first_token_time) {
        return RAC_SUCCESS;
    }

    tracker.first_token_time_ms = get_current_time_ms();
    tracker.has_first_token_time = true;

    double time_to_first_token_ms =
        static_cast<double>(tracker.first_token_time_ms - tracker.start_time_ms);

    log_debug("LLM.Analytics", "First token received for %s: %.1fms", generation_id,
              time_to_first_token_ms);

    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_track_streaming_update(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    int32_t tokens_generated
) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    // Only applicable for streaming generations
    if (!it->second.is_streaming) {
        return RAC_SUCCESS;
    }

    // Event would be published here in full implementation
    (void)tokens_generated;

    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_complete_generation(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    int32_t input_tokens,
    int32_t output_tokens,
    const char* model_id
) {
    if (!handle || !generation_id || !model_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    GenerationTracker tracker = it->second;
    handle->active_generations.erase(it);

    int64_t end_time_ms = get_current_time_ms();
    double total_time_sec =
        static_cast<double>(end_time_ms - tracker.start_time_ms) / 1000.0;
    double tokens_per_second =
        total_time_sec > 0 ? static_cast<double>(output_tokens) / total_time_sec : 0;

    // Calculate TTFT for streaming generations
    if (tracker.is_streaming && tracker.has_first_token_time) {
        double ttft_ms = static_cast<double>(tracker.first_token_time_ms - tracker.start_time_ms);
        handle->total_time_to_first_token_ms += ttft_ms;
        handle->streaming_ttft_count++;
    }

    // Update metrics
    handle->total_generations++;
    if (tracker.is_streaming) {
        handle->streaming_generations++;
    } else {
        handle->non_streaming_generations++;
    }
    handle->total_tokens_per_second += tokens_per_second;
    handle->total_input_tokens += input_tokens;
    handle->total_output_tokens += output_tokens;
    handle->last_event_time_ms = end_time_ms;
    handle->has_last_event_time = true;

    const char* mode_str = tracker.is_streaming ? "streaming" : "non-streaming";
    log_debug("LLM.Analytics", "Generation completed (%s): %s", mode_str, generation_id);

    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_track_generation_failed(
    rac_llm_analytics_handle_t handle,
    const char* generation_id,
    rac_result_t error_code,
    const char* error_message
) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->active_generations.erase(generation_id);
    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("LLM.Analytics", "Generation failed %s: %d - %s", generation_id, error_code,
              error_message ? error_message : "");

    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_track_error(
    rac_llm_analytics_handle_t handle,
    rac_result_t error_code,
    const char* error_message,
    const char* operation,
    const char* model_id,
    const char* generation_id
) {
    if (!handle) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->last_event_time_ms = get_current_time_ms();
    handle->has_last_event_time = true;

    log_error("LLM.Analytics", "LLM error in %s: %d - %s (model: %s, gen: %s)",
              operation ? operation : "unknown", error_code, error_message ? error_message : "",
              model_id ? model_id : "none", generation_id ? generation_id : "none");

    return RAC_SUCCESS;
}

rac_result_t rac_llm_analytics_get_metrics(
    rac_llm_analytics_handle_t handle,
    rac_generation_metrics_t* out_metrics
) {
    if (!handle || !out_metrics) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    out_metrics->total_events = handle->total_generations;
    out_metrics->start_time_ms = handle->start_time_ms;
    out_metrics->last_event_time_ms =
        handle->has_last_event_time ? handle->last_event_time_ms : 0;
    out_metrics->total_generations = handle->total_generations;
    out_metrics->streaming_generations = handle->streaming_generations;
    out_metrics->non_streaming_generations = handle->non_streaming_generations;

    // Average TTFT only counts streaming generations that had TTFT recorded
    out_metrics->average_time_to_first_token_ms =
        handle->streaming_ttft_count > 0
            ? handle->total_time_to_first_token_ms / static_cast<double>(handle->streaming_ttft_count)
            : 0;

    out_metrics->average_tokens_per_second =
        handle->total_generations > 0
            ? handle->total_tokens_per_second / static_cast<double>(handle->total_generations)
            : 0;

    out_metrics->total_input_tokens = handle->total_input_tokens;
    out_metrics->total_output_tokens = handle->total_output_tokens;

    return RAC_SUCCESS;
}

}  // extern "C"
