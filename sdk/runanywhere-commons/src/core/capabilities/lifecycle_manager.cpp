/**
 * @file lifecycle_manager.cpp
 * @brief RunAnywhere Commons - Lifecycle Manager Implementation
 *
 * C++ port of Swift's ManagedLifecycle.swift from:
 * Sources/RunAnywhere/Core/Capabilities/ManagedLifecycle.swift
 *
 * IMPLEMENTATION NOTE: This is a direct 1:1 port of the Swift code.
 * Do not add, remove, or modify any behavior that isn't in the Swift source.
 */

#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <new>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

namespace {

/**
 * Internal lifecycle manager state.
 * Mirrors Swift's ManagedLifecycle properties.
 */
struct LifecycleManager {
    // Configuration
    rac_resource_type_t resource_type{RAC_RESOURCE_TYPE_LLM_MODEL};
    std::string logger_category{};
    void* user_data{nullptr};

    // Callbacks
    rac_lifecycle_create_service_fn create_fn{nullptr};
    rac_lifecycle_destroy_service_fn destroy_fn{nullptr};

    // State (mirrors Swift's lifecycle properties)
    std::atomic<rac_lifecycle_state_t> state{RAC_LIFECYCLE_STATE_IDLE};
    std::string current_model_path{};  // File path used for loading
    std::string
        current_model_id{};  // Model identifier for telemetry (e.g., "sherpa-onnx-whisper-tiny.en")
    std::string current_model_name{};  // Human-readable name (e.g., "Sherpa Whisper Tiny (ONNX)")
    std::atomic<rac_handle_t> current_service{nullptr};

    // Metrics (mirrors Swift's ManagedLifecycle metrics)
    int32_t load_count{0};
    double total_load_time_ms{0.0};
    int32_t failed_loads{0};
    int32_t total_unloads{0};
    int64_t start_time_ms{0};
    int64_t last_event_time_ms{0};

    // Thread safety
    std::mutex mutex{};

    LifecycleManager() {
        // Set start time (mirrors Swift's startTime = Date())
        auto now = std::chrono::system_clock::now();
        auto duration = now.time_since_epoch();
        start_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
    }
};

int64_t current_time_ms() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

/**
 * Track lifecycle event via EventPublisher.
 * Mirrors Swift's trackEvent(type:modelId:durationMs:error:)
 */
void track_lifecycle_event(LifecycleManager* mgr, const char* event_type, const char* model_id,
                           double duration_ms, rac_result_t error_code) {
    // Determine event category based on resource type
    // Mirrors Swift's createEvent() switch on resourceType
    rac_event_category_t category = RAC_EVENT_CATEGORY_MODEL;
    switch (mgr->resource_type) {
        case RAC_RESOURCE_TYPE_LLM_MODEL:
            category = RAC_EVENT_CATEGORY_LLM;
            break;
        case RAC_RESOURCE_TYPE_STT_MODEL:
            category = RAC_EVENT_CATEGORY_STT;
            break;
        case RAC_RESOURCE_TYPE_TTS_VOICE:
            category = RAC_EVENT_CATEGORY_TTS;
            break;
        case RAC_RESOURCE_TYPE_VAD_MODEL:
        case RAC_RESOURCE_TYPE_DIARIZATION_MODEL:
        default:
            // category already initialized to RAC_EVENT_CATEGORY_MODEL
            break;
    }

    // Build properties JSON (simplified version)
    char properties[512];
    if (error_code != RAC_SUCCESS) {
        snprintf(properties, sizeof(properties),
                 R"({"modelId":"%s","durationMs":%.1f,"errorCode":%d})", model_id ? model_id : "",
                 duration_ms, error_code);
    } else if (duration_ms > 0) {
        snprintf(properties, sizeof(properties), R"({"modelId":"%s","durationMs":%.1f})",
                 model_id ? model_id : "", duration_ms);
    } else {
        snprintf(properties, sizeof(properties), R"({"modelId":"%s"})", model_id ? model_id : "");
    }

    // Track event (mirrors Swift's EventPublisher.shared.track(event))
    rac_event_track(event_type, category, RAC_EVENT_DESTINATION_ALL, properties);

    mgr->last_event_time_ms = current_time_ms();
}

}  // namespace

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_lifecycle_create(const rac_lifecycle_config_t* config,
                                  rac_lifecycle_create_service_fn create_fn,
                                  rac_lifecycle_destroy_service_fn destroy_fn,
                                  rac_handle_t* out_handle) {
    if (config == nullptr || create_fn == nullptr || out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = new (std::nothrow) LifecycleManager();
    if (!mgr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    mgr->resource_type = config->resource_type;
    mgr->logger_category = config->logger_category ? config->logger_category : "Lifecycle";
    mgr->user_data = config->user_data;
    mgr->create_fn = create_fn;
    mgr->destroy_fn = destroy_fn;

    *out_handle = static_cast<rac_handle_t>(mgr);
    return RAC_SUCCESS;
}

rac_result_t rac_lifecycle_load(rac_handle_t handle, const char* model_path, const char* model_id,
                                const char* model_name, rac_handle_t* out_service) {
    if (handle == nullptr || model_path == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // If model_id is null, use model_path as model_id
    if (model_id == nullptr) {
        model_id = model_path;
    }
    // If model_name is null, use model_id as model_name
    if (model_name == nullptr) {
        model_name = model_id;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    // Check if already loaded with same path - skip duplicate events
    // Mirrors Swift: if await lifecycle.currentResourceId == modelId
    if (mgr->state.load() == RAC_LIFECYCLE_STATE_LOADED && mgr->current_model_path == model_path &&
        mgr->current_service.load() != nullptr) {
        // Mirrors Swift: logger.info("Model already loaded, skipping duplicate load")
        RAC_LOG_INFO(mgr->logger_category.c_str(), "Model already loaded, skipping duplicate load");
        *out_service = mgr->current_service.load();
        return RAC_SUCCESS;
    }

    // Track load started (mirrors Swift: trackEvent(type: .loadStarted))
    int64_t start_time = current_time_ms();
    mgr->state.store(RAC_LIFECYCLE_STATE_LOADING);
    track_lifecycle_event(mgr, "load.started", model_id, 0.0, RAC_SUCCESS);

    RAC_LOG_INFO(mgr->logger_category.c_str(), "Loading model: %s (path: %s)", model_id,
                 model_path);

    // Create service via callback - pass the PATH for loading
    rac_handle_t service = nullptr;
    rac_result_t result = mgr->create_fn(model_path, mgr->user_data, &service);

    auto load_time_ms = static_cast<double>(current_time_ms() - start_time);

    if (result == RAC_SUCCESS && service != nullptr) {
        // Success - store path, model_id, and model_name separately
        mgr->current_model_path = model_path;
        mgr->current_model_id = model_id;      // Model identifier for telemetry
        mgr->current_model_name = model_name;  // Human-readable name for telemetry
        mgr->current_service.store(service);
        mgr->state.store(RAC_LIFECYCLE_STATE_LOADED);

        // Track load completed (mirrors Swift: trackEvent(type: .loadCompleted))
        track_lifecycle_event(mgr, "load.completed", model_id, load_time_ms, RAC_SUCCESS);

        // Update metrics (mirrors Swift: loadCount += 1, totalLoadTime += loadTime)
        mgr->load_count++;
        mgr->total_load_time_ms += load_time_ms;

        RAC_LOG_INFO(mgr->logger_category.c_str(), "Loaded model in %dms",
                     static_cast<int>(load_time_ms));

        *out_service = service;
        return RAC_SUCCESS;
    }

    // Failure - mirrors Swift catch block
    mgr->state.store(RAC_LIFECYCLE_STATE_FAILED);
    mgr->failed_loads++;

    // Track load failed (mirrors Swift: trackEvent(type: .loadFailed))
    track_lifecycle_event(mgr, "load.failed", model_id, load_time_ms, result);

    RAC_LOG_ERROR(mgr->logger_category.c_str(), "Failed to load model");

    return result;
}

rac_result_t rac_lifecycle_unload(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    // Mirrors Swift: if let modelId = await lifecycle.currentResourceId
    if (!mgr->current_model_id.empty()) {
        RAC_LOG_INFO(mgr->logger_category.c_str(), "Unloading model: %s",
                     mgr->current_model_id.c_str());

        // Destroy service if callback provided.
        // Store nullptr BEFORE calling destroy_fn so that concurrent cancel()
        // reads via get_service() see nullptr rather than a dangling pointer.
        rac_handle_t svc = mgr->current_service.load();
        mgr->current_service.store(nullptr);
        if (mgr->destroy_fn != nullptr && svc != nullptr) {
            mgr->destroy_fn(svc, mgr->user_data);
        }

        // Track unload event (mirrors Swift: trackEvent(type: .unloaded))
        track_lifecycle_event(mgr, "unloaded", mgr->current_model_id.c_str(), 0.0, RAC_SUCCESS);

        mgr->total_unloads++;
    }

    // Reset state
    mgr->current_model_path.clear();
    mgr->current_model_id.clear();
    mgr->current_model_name.clear();
    mgr->current_service.store(nullptr);
    mgr->state.store(RAC_LIFECYCLE_STATE_IDLE);

    return RAC_SUCCESS;
}

rac_result_t rac_lifecycle_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    // Track unload if currently loaded (mirrors Swift reset())
    if (!mgr->current_model_id.empty()) {
        track_lifecycle_event(mgr, "unloaded", mgr->current_model_id.c_str(), 0.0, RAC_SUCCESS);

        // Store nullptr BEFORE calling destroy_fn (same reasoning as unload)
        rac_handle_t svc = mgr->current_service.load();
        mgr->current_service.store(nullptr);
        if (mgr->destroy_fn != nullptr && svc != nullptr) {
            mgr->destroy_fn(svc, mgr->user_data);
        }
    }

    // Reset all state
    mgr->current_model_path.clear();
    mgr->current_model_id.clear();
    mgr->current_model_name.clear();
    mgr->current_service.store(nullptr);
    mgr->state.store(RAC_LIFECYCLE_STATE_IDLE);

    return RAC_SUCCESS;
}

rac_lifecycle_state_t rac_lifecycle_get_state(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    return mgr->state.load();
}

rac_bool_t rac_lifecycle_is_loaded(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    return mgr->state.load() == RAC_LIFECYCLE_STATE_LOADED ? RAC_TRUE : RAC_FALSE;
}

const char* rac_lifecycle_get_model_id(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->current_model_id.empty()) {
        return nullptr;
    }
    return mgr->current_model_id.c_str();
}

const char* rac_lifecycle_get_model_name(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->current_model_name.empty()) {
        return nullptr;
    }
    return mgr->current_model_name.c_str();
}

rac_handle_t rac_lifecycle_get_service(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    // Atomic load — safe to call without the lifecycle mutex.
    // This is used by cancel() paths which intentionally skip locking
    // to avoid deadlock with streaming operations.
    return mgr->current_service.load(std::memory_order_acquire);
}

rac_result_t rac_lifecycle_require_service(rac_handle_t handle, rac_handle_t* out_service) {
    if (handle == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);

    if (mgr->state.load() != RAC_LIFECYCLE_STATE_LOADED || mgr->current_service.load() == nullptr) {
        rac_error_set_details("Service not loaded - call load() first");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    *out_service = mgr->current_service.load();
    return RAC_SUCCESS;
}

void rac_lifecycle_track_error(rac_handle_t handle, rac_result_t error_code,
                               const char* operation) {
    if (handle == nullptr) {
        return;
    }

    // Note: handle parameter reserved for future use (e.g., category from mgr->resource_type)
    (void)handle;

    // Build error event properties
    char properties[256];
    snprintf(properties, sizeof(properties),
             R"({"operation":"%s","errorCode":%d,"errorMessage":"%s"})",
             operation ? operation : "unknown", error_code, rac_error_message(error_code));

    // Track error event (mirrors Swift: EventPublisher.shared.track(errorEvent))
    rac_event_track("error.operation", RAC_EVENT_CATEGORY_ERROR, RAC_EVENT_DESTINATION_ALL,
                    properties);
}

rac_result_t rac_lifecycle_get_metrics(rac_handle_t handle, rac_lifecycle_metrics_t* out_metrics) {
    if (handle == nullptr || out_metrics == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    // Mirrors Swift's getLifecycleMetrics()
    out_metrics->total_events = mgr->load_count + mgr->total_unloads + mgr->failed_loads;
    out_metrics->start_time_ms = mgr->start_time_ms;
    out_metrics->last_event_time_ms = mgr->last_event_time_ms;
    out_metrics->total_loads = mgr->load_count + mgr->failed_loads;
    out_metrics->successful_loads = mgr->load_count;
    out_metrics->failed_loads = mgr->failed_loads;
    out_metrics->average_load_time_ms =
        mgr->load_count > 0 ? mgr->total_load_time_ms / static_cast<double>(mgr->load_count) : 0.0;
    out_metrics->total_unloads = mgr->total_unloads;

    return RAC_SUCCESS;
}

void rac_lifecycle_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);

    // Unload before destroy
    rac_lifecycle_unload(handle);

    delete mgr;
}

const char* rac_lifecycle_state_name(rac_lifecycle_state_t state) {
    switch (state) {
        case RAC_LIFECYCLE_STATE_IDLE:
            return "idle";
        case RAC_LIFECYCLE_STATE_LOADING:
            return "loading";
        case RAC_LIFECYCLE_STATE_LOADED:
            return "loaded";
        case RAC_LIFECYCLE_STATE_FAILED:
            return "failed";
        default:
            return "unknown";
    }
}

const char* rac_resource_type_name(rac_resource_type_t type) {
    switch (type) {
        case RAC_RESOURCE_TYPE_LLM_MODEL:
            return "llmModel";
        case RAC_RESOURCE_TYPE_STT_MODEL:
            return "sttModel";
        case RAC_RESOURCE_TYPE_TTS_VOICE:
            return "ttsVoice";
        case RAC_RESOURCE_TYPE_VAD_MODEL:
            return "vadModel";
        case RAC_RESOURCE_TYPE_DIARIZATION_MODEL:
            return "diarizationModel";
        case RAC_RESOURCE_TYPE_VLM_MODEL:
            return "vlmModel";
        case RAC_RESOURCE_TYPE_DIFFUSION_MODEL:
            return "diffusionModel";
        default:
            return "unknown";
    }
}

}  // extern "C"
