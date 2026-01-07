/**
 * @file streaming_metrics.cpp
 * @brief RunAnywhere Commons - LLM Streaming Metrics Implementation
 *
 * C++ port of Swift's StreamingMetricsCollector and GenerationAnalyticsService.
 * Swift Source: Sources/RunAnywhere/Features/LLM/LLMCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/LLM/Analytics/GenerationAnalyticsService.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 */

#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/llm/rac_llm_metrics.h"

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

// =============================================================================
// STREAMING METRICS COLLECTOR INTERNAL STRUCTURE
// =============================================================================

struct rac_streaming_metrics_collector {
    // Configuration
    std::string model_id{};
    std::string generation_id{};
    int32_t prompt_length{0};

    // Timing
    int64_t start_time_ms{0};
    int64_t first_token_time_ms{0};
    int64_t end_time_ms{0};

    // State
    std::string full_text{};
    int32_t token_count{0};
    bool first_token_recorded{false};
    bool is_complete{false};
    rac_result_t error_code{RAC_SUCCESS};

    // Actual token counts from backend (0 = use estimation)
    int32_t actual_input_tokens{0};
    int32_t actual_output_tokens{0};

    // Thread safety
    std::mutex mutex{};

    rac_streaming_metrics_collector() = default;
};

// =============================================================================
// GENERATION TRACKER (Internal)
// =============================================================================

struct GenerationTracker {
    std::string model_id{};
    int64_t start_time_ms{0};
    int64_t first_token_time_ms{0};
    bool is_streaming{false};
    bool first_token_recorded{false};

    GenerationTracker() = default;
};

// =============================================================================
// GENERATION ANALYTICS SERVICE INTERNAL STRUCTURE
// =============================================================================

struct rac_generation_analytics {
    // Active generations
    std::map<std::string, GenerationTracker> active_generations{};

    // Aggregated metrics
    int32_t total_generations{0};
    int32_t streaming_generations{0};
    int32_t non_streaming_generations{0};
    double total_tokens_per_second{0.0};
    double total_ttft_seconds{0.0};
    int32_t ttft_count{0};
    int64_t total_input_tokens{0};
    int64_t total_output_tokens{0};
    int64_t start_time_ms{0};
    int64_t last_event_time_ms{0};

    // Thread safety
    std::mutex mutex{};

    rac_generation_analytics() { start_time_ms = rac_get_current_time_ms(); }
};

// =============================================================================
// STREAMING METRICS COLLECTOR API
// =============================================================================

rac_result_t rac_streaming_metrics_create(const char* model_id, const char* generation_id,
                                          int32_t prompt_length,
                                          rac_streaming_metrics_handle_t* out_handle) {
    if (!model_id || !generation_id || !out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_streaming_metrics_collector* collector = new rac_streaming_metrics_collector();
    collector->model_id = model_id;
    collector->generation_id = generation_id;
    collector->prompt_length = prompt_length;

    *out_handle = collector;
    return RAC_SUCCESS;
}

void rac_streaming_metrics_destroy(rac_streaming_metrics_handle_t handle) {
    if (handle) {
        delete handle;
    }
}

rac_result_t rac_streaming_metrics_mark_start(rac_streaming_metrics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->start_time_ms = rac_get_current_time_ms();
    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_record_token(rac_streaming_metrics_handle_t handle,
                                                const char* token) {
    if (!handle || !token) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Record first token time
    if (!handle->first_token_recorded) {
        handle->first_token_time_ms = rac_get_current_time_ms();
        handle->first_token_recorded = true;
    }

    // Accumulate text and count
    handle->full_text += token;
    handle->token_count++;

    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_mark_complete(rac_streaming_metrics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->end_time_ms = rac_get_current_time_ms();
    handle->is_complete = true;
    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_mark_failed(rac_streaming_metrics_handle_t handle,
                                               rac_result_t error_code) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->end_time_ms = rac_get_current_time_ms();
    handle->is_complete = true;
    handle->error_code = error_code;
    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_get_result(rac_streaming_metrics_handle_t handle,
                                              rac_streaming_result_t* out_result) {
    if (!handle || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Calculate latency
    int64_t end_time = handle->end_time_ms > 0 ? handle->end_time_ms : rac_get_current_time_ms();
    double latency_ms = static_cast<double>(end_time - handle->start_time_ms);

    // Calculate TTFT
    double ttft_ms = 0.0;
    if (handle->first_token_recorded && handle->start_time_ms > 0) {
        ttft_ms = static_cast<double>(handle->first_token_time_ms - handle->start_time_ms);
    }

    // Use actual token counts from backend if available, otherwise estimate
    int32_t input_tokens;
    int32_t output_tokens;

    if (handle->actual_input_tokens > 0) {
        input_tokens = handle->actual_input_tokens;
    } else {
        // Fallback: estimate ~4 chars per token
        input_tokens = handle->prompt_length > 0 ? (handle->prompt_length / 4) : 1;
        if (input_tokens < 1)
            input_tokens = 1;
    }

    if (handle->actual_output_tokens > 0) {
        output_tokens = handle->actual_output_tokens;
    } else {
        // Fallback: estimate ~4 chars per token
        output_tokens = static_cast<int32_t>(handle->full_text.length() / 4);
        if (output_tokens < 1)
            output_tokens = 1;
    }

    // Tokens per second
    double tokens_per_second = 0.0;
    if (latency_ms > 0) {
        tokens_per_second = static_cast<double>(output_tokens) / (latency_ms / 1000.0);
    }

    // Populate result
    out_result->text = rac_strdup(handle->full_text.c_str());
    out_result->thinking_content = nullptr;
    out_result->input_tokens = input_tokens;
    out_result->output_tokens = output_tokens;
    out_result->model_id = rac_strdup(handle->model_id.c_str());
    out_result->latency_ms = latency_ms;
    out_result->tokens_per_second = tokens_per_second;
    out_result->ttft_ms = ttft_ms;
    out_result->thinking_tokens = 0;
    out_result->response_tokens = output_tokens;

    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_get_ttft(rac_streaming_metrics_handle_t handle,
                                            double* out_ttft_ms) {
    if (!handle || !out_ttft_ms) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->first_token_recorded || handle->start_time_ms == 0) {
        *out_ttft_ms = 0.0;
    } else {
        *out_ttft_ms = static_cast<double>(handle->first_token_time_ms - handle->start_time_ms);
    }

    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_get_token_count(rac_streaming_metrics_handle_t handle,
                                                   int32_t* out_token_count) {
    if (!handle || !out_token_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_token_count = handle->token_count;
    return RAC_SUCCESS;
}

rac_result_t rac_streaming_metrics_get_text(rac_streaming_metrics_handle_t handle,
                                            char** out_text) {
    if (!handle || !out_text) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_text = rac_strdup(handle->full_text.c_str());
    return *out_text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t rac_streaming_metrics_set_token_counts(rac_streaming_metrics_handle_t handle,
                                                    int32_t input_tokens,
                                                    int32_t output_tokens) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->actual_input_tokens = input_tokens;
    handle->actual_output_tokens = output_tokens;
    return RAC_SUCCESS;
}

// =============================================================================
// GENERATION ANALYTICS SERVICE API
// =============================================================================

rac_result_t rac_generation_analytics_create(rac_generation_analytics_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_generation_analytics* service = new rac_generation_analytics();

    RAC_LOG_INFO("GenerationAnalytics", "Service created");

    *out_handle = service;
    return RAC_SUCCESS;
}

void rac_generation_analytics_destroy(rac_generation_analytics_handle_t handle) {
    if (handle) {
        delete handle;
        RAC_LOG_DEBUG("GenerationAnalytics", "Service destroyed");
    }
}

rac_result_t rac_generation_analytics_start(rac_generation_analytics_handle_t handle,
                                            const char* generation_id, const char* model_id) {
    if (!handle || !generation_id || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    GenerationTracker tracker;
    tracker.model_id = model_id;
    tracker.start_time_ms = rac_get_current_time_ms();
    tracker.is_streaming = false;
    tracker.first_token_recorded = false;

    handle->active_generations[generation_id] = tracker;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_start_streaming(rac_generation_analytics_handle_t handle,
                                                      const char* generation_id,
                                                      const char* model_id) {
    if (!handle || !generation_id || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    GenerationTracker tracker;
    tracker.model_id = model_id;
    tracker.start_time_ms = rac_get_current_time_ms();
    tracker.is_streaming = true;
    tracker.first_token_recorded = false;

    handle->active_generations[generation_id] = tracker;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_track_first_token(rac_generation_analytics_handle_t handle,
                                                        const char* generation_id) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    GenerationTracker& tracker = it->second;

    // Only track for streaming, only once
    if (!tracker.is_streaming || tracker.first_token_recorded) {
        return RAC_SUCCESS;
    }

    tracker.first_token_time_ms = rac_get_current_time_ms();
    tracker.first_token_recorded = true;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_track_streaming_update(
    rac_generation_analytics_handle_t handle, const char* generation_id, int32_t tokens_generated) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    // Update last event time
    handle->last_event_time_ms = rac_get_current_time_ms();

    // Events could be published here if needed
    (void)tokens_generated;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_complete(rac_generation_analytics_handle_t handle,
                                               const char* generation_id, int32_t input_tokens,
                                               int32_t output_tokens, const char* model_id) {
    if (!handle || !generation_id || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->active_generations.find(generation_id);
    if (it == handle->active_generations.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    GenerationTracker tracker = it->second;
    handle->active_generations.erase(it);

    int64_t end_time = rac_get_current_time_ms();
    double total_time_seconds = static_cast<double>(end_time - tracker.start_time_ms) / 1000.0;
    double tokens_per_second =
        total_time_seconds > 0 ? static_cast<double>(output_tokens) / total_time_seconds : 0.0;

    // Calculate TTFT for streaming generations
    if (tracker.is_streaming && tracker.first_token_recorded) {
        double ttft_seconds =
            static_cast<double>(tracker.first_token_time_ms - tracker.start_time_ms) / 1000.0;
        handle->total_ttft_seconds += ttft_seconds;
        handle->ttft_count++;
    }

    // Update aggregated metrics
    handle->total_generations++;
    if (tracker.is_streaming) {
        handle->streaming_generations++;
    } else {
        handle->non_streaming_generations++;
    }
    handle->total_tokens_per_second += tokens_per_second;
    handle->total_input_tokens += input_tokens;
    handle->total_output_tokens += output_tokens;
    handle->last_event_time_ms = end_time;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_track_failed(rac_generation_analytics_handle_t handle,
                                                   const char* generation_id,
                                                   rac_result_t error_code) {
    if (!handle || !generation_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Remove from active generations
    handle->active_generations.erase(generation_id);
    handle->last_event_time_ms = rac_get_current_time_ms();

    (void)error_code;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_get_metrics(rac_generation_analytics_handle_t handle,
                                                  rac_generation_metrics_t* out_metrics) {
    if (!handle || !out_metrics) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Average TTFT only for streaming generations with TTFT recorded
    double avg_ttft_ms =
        handle->ttft_count > 0
            ? (handle->total_ttft_seconds / static_cast<double>(handle->ttft_count)) * 1000.0
            : 0.0;

    // Average tokens per second
    double avg_tps =
        handle->total_generations > 0
            ? handle->total_tokens_per_second / static_cast<double>(handle->total_generations)
            : 0.0;

    out_metrics->total_generations = handle->total_generations;
    out_metrics->streaming_generations = handle->streaming_generations;
    out_metrics->non_streaming_generations = handle->non_streaming_generations;
    out_metrics->average_ttft_ms = avg_ttft_ms;
    out_metrics->average_tokens_per_second = avg_tps;
    out_metrics->total_input_tokens = handle->total_input_tokens;
    out_metrics->total_output_tokens = handle->total_output_tokens;
    out_metrics->start_time_ms = handle->start_time_ms;
    out_metrics->last_event_time_ms = handle->last_event_time_ms;

    return RAC_SUCCESS;
}

rac_result_t rac_generation_analytics_reset(rac_generation_analytics_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->active_generations.clear();
    handle->total_generations = 0;
    handle->streaming_generations = 0;
    handle->non_streaming_generations = 0;
    handle->total_tokens_per_second = 0.0;
    handle->total_ttft_seconds = 0.0;
    handle->ttft_count = 0;
    handle->total_input_tokens = 0;
    handle->total_output_tokens = 0;
    handle->start_time_ms = rac_get_current_time_ms();
    handle->last_event_time_ms = 0;

    return RAC_SUCCESS;
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

void rac_streaming_result_free(rac_streaming_result_t* result) {
    if (!result) {
        return;
    }

    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
    if (result->thinking_content) {
        free(result->thinking_content);
        result->thinking_content = nullptr;
    }
    if (result->model_id) {
        free(result->model_id);
        result->model_id = nullptr;
    }
}
