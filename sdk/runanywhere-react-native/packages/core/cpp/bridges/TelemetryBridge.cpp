/**
 * TelemetryBridge.cpp
 *
 * C++ telemetry bridge implementation for React Native.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift
 *
 * Key insight from Swift/Kotlin:
 * - C++ telemetry manager builds JSON and batches events
 * - Platform SDK provides HTTP callback for sending
 * - Analytics events are routed through C++ callback to telemetry manager
 */

#include "TelemetryBridge.hpp"
#include "InitBridge.hpp"
#include "rac_dev_config.h"

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "TelemetryBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf("[TelemetryBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[TelemetryBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[TelemetryBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// Forward declarations for callbacks
static void telemetryHttpCallback(
    void* userData,
    const char* endpoint,
    const char* jsonBody,
    size_t jsonLength,
    rac_bool_t requiresAuth
);

static void analyticsEventCallback(
    rac_event_type_t type,
    const rac_analytics_event_data_t* data,
    void* userData
);

// ============================================================================
// Singleton
// ============================================================================

TelemetryBridge& TelemetryBridge::shared() {
    static TelemetryBridge instance;
    return instance;
}

TelemetryBridge::~TelemetryBridge() {
    shutdown();
}

// ============================================================================
// Lifecycle
// ============================================================================

void TelemetryBridge::initialize(
    rac_environment_t environment,
    const std::string& deviceId,
    const std::string& deviceModel,
    const std::string& osVersion,
    const std::string& sdkVersion
) {
    std::lock_guard<std::mutex> lock(mutex_);

    // Destroy existing manager if any
    if (manager_) {
        rac_telemetry_manager_flush(manager_);
        rac_telemetry_manager_destroy(manager_);
        manager_ = nullptr;
    }

    environment_ = environment;

    LOGI("Creating telemetry manager: device=%s, model=%s, os=%s, sdk=%s, env=%d",
         deviceId.c_str(), deviceModel.c_str(), osVersion.c_str(), sdkVersion.c_str(), environment);

    // Create telemetry manager
    // Matches Swift: rac_telemetry_manager_create(Environment.toC(environment), did, plat, ver)
    manager_ = rac_telemetry_manager_create(
        environment,
        deviceId.c_str(),
        "react-native",  // platform
        sdkVersion.c_str()
    );

    if (!manager_) {
        LOGE("Failed to create telemetry manager");
        return;
    }

    // Set device info
    // Matches Swift: rac_telemetry_manager_set_device_info(manager, model, os)
    rac_telemetry_manager_set_device_info(manager_, deviceModel.c_str(), osVersion.c_str());

    // Register HTTP callback - this is where platform provides HTTP transport
    // Matches Swift: rac_telemetry_manager_set_http_callback(manager, telemetryHttpCallback, userData)
    rac_telemetry_manager_set_http_callback(manager_, telemetryHttpCallback, this);

    LOGI("Telemetry manager initialized successfully");
}

void TelemetryBridge::shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);

    // Unregister events callback first
    if (eventsCallbackRegistered_) {
        rac_analytics_events_set_callback(nullptr, nullptr);
        eventsCallbackRegistered_ = false;
    }

    if (manager_) {
        LOGI("Shutting down telemetry manager...");

        // Flush pending events
        rac_telemetry_manager_flush(manager_);

        // Destroy manager
        rac_telemetry_manager_destroy(manager_);
        manager_ = nullptr;

        LOGI("Telemetry manager destroyed");
    }
}

bool TelemetryBridge::isInitialized() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return manager_ != nullptr;
}

// ============================================================================
// Event Tracking
// ============================================================================

void TelemetryBridge::trackAnalyticsEvent(
    rac_event_type_t eventType,
    const rac_analytics_event_data_t* data
) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!manager_) {
        LOGD("Telemetry not initialized, skipping event");
        return;
    }

    // Route to C++ telemetry manager
    // Matches Swift: rac_telemetry_manager_track_analytics(mgr, type, data)
    rac_result_t result = rac_telemetry_manager_track_analytics(manager_, eventType, data);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to track analytics event: %d", result);
    }
}

void TelemetryBridge::flush() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!manager_) {
        return;
    }

    LOGI("Flushing telemetry events...");
    rac_telemetry_manager_flush(manager_);
}

// ============================================================================
// Events Callback Registration
// ============================================================================

void TelemetryBridge::registerEventsCallback() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (eventsCallbackRegistered_) {
        return;
    }

    // Register analytics callback - routes events to telemetry manager
    // Matches Swift: rac_analytics_events_set_callback(analyticsEventCallback, nil)
    rac_result_t result = rac_analytics_events_set_callback(analyticsEventCallback, this);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to register analytics events callback: %d", result);
        return;
    }

    eventsCallbackRegistered_ = true;
    LOGI("Analytics events callback registered");
}

void TelemetryBridge::unregisterEventsCallback() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!eventsCallbackRegistered_) {
        return;
    }

    rac_analytics_events_set_callback(nullptr, nullptr);
    eventsCallbackRegistered_ = false;
    LOGI("Analytics events callback unregistered");
}

// ============================================================================
// HTTP Callback (Platform provides HTTP transport)
// ============================================================================

/**
 * HTTP callback invoked by C++ telemetry manager when it's time to send events.
 *
 * C++ has already:
 * - Built the JSON payload
 * - Determined the endpoint
 * - Batched the events
 *
 * We just need to make the HTTP POST request using platform-native HTTP.
 *
 * Matches Swift's telemetryHttpCallback in CppBridge+Telemetry.swift
 */
static void telemetryHttpCallback(
    void* userData,
    const char* endpoint,
    const char* jsonBody,
    size_t jsonLength,
    rac_bool_t requiresAuth
) {
    if (!endpoint || !jsonBody) {
        LOGE("Invalid telemetry HTTP callback parameters");
        return;
    }

    auto* bridge = static_cast<TelemetryBridge*>(userData);
    if (!bridge) {
        LOGE("TelemetryBridge not available for HTTP callback");
        return;
    }

    std::string path(endpoint);
    std::string json(jsonBody, jsonLength);
    rac_environment_t env = bridge->getEnvironment();

    LOGI("Telemetry HTTP callback: endpoint=%s, bodyLen=%zu, env=%d", path.c_str(), jsonLength, env);

    // Build full URL based on environment
    // Matches Swift HTTPService logic
    std::string baseURL;
    std::string apiKey;

    if (env == RAC_ENV_DEVELOPMENT) {
        // Development: Use Supabase from C++ dev config
        const char* devUrl = rac_dev_config_get_supabase_url();
        const char* devKey = rac_dev_config_get_supabase_key();

        baseURL = devUrl ? devUrl : "https://fhtgjtxuoikwwouxqzrn.supabase.co";
        apiKey = devKey ? devKey : "";

        LOGD("Telemetry using Supabase: %s", baseURL.c_str());
    } else {
        // Production/Staging: Use Railway
        baseURL = "https://api.runanywhere.ai";
        apiKey = "";  // API key handled by backend
    }

    std::string fullURL = baseURL + path;

    LOGI("Telemetry POST to: %s", fullURL.c_str());

    // Use platform-native HTTP (same as device registration)
    auto [success, statusCode, responseBody, errorMessage] =
        InitBridge::shared().httpPostSync(fullURL, json, apiKey);

    if (success) {
        LOGI("✅ Telemetry sent successfully (status=%d)", statusCode);

        // Notify C++ that HTTP completed
        rac_telemetry_manager_http_complete(
            bridge->getHandle(),
            RAC_TRUE,
            responseBody.c_str(),
            nullptr
        );
    } else {
        LOGE("❌ Telemetry HTTP failed: status=%d, error=%s", statusCode, errorMessage.c_str());

        // Notify C++ of failure
        rac_telemetry_manager_http_complete(
            bridge->getHandle(),
            RAC_FALSE,
            nullptr,
            errorMessage.c_str()
        );
    }
}

// ============================================================================
// Analytics Events Callback
// ============================================================================

/**
 * Analytics callback - receives events from C++ analytics system.
 *
 * Routes events to telemetry manager for batching and sending.
 *
 * Matches Swift's analyticsEventCallback in CppBridge+Telemetry.swift
 */
static void analyticsEventCallback(
    rac_event_type_t type,
    const rac_analytics_event_data_t* data,
    void* userData
) {
    if (!data) {
        return;
    }

    auto* bridge = static_cast<TelemetryBridge*>(userData);
    if (!bridge) {
        return;
    }

    // Forward to telemetry manager
    // C++ handles JSON building, batching, etc.
    bridge->trackAnalyticsEvent(type, data);
}

} // namespace bridges
} // namespace runanywhere

