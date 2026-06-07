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
#include "AuthBridge.hpp"
#include "ExternalConfigGuard.hpp"
#include "rac_dev_config.h"
#include "rac_sdk_event_stream.h"  // rac_events_set_telemetry_sink

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "TelemetryBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf("[TelemetryBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[TelemetryBridge WARN] "); printf(__VA_ARGS__); printf("\n")
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

    // Detach the telemetry sink first so the C++ router stops feeding events
    // into a manager we are about to destroy.
    if (eventsCallbackRegistered_) {
        rac_events_set_telemetry_sink(nullptr);
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

    if (!manager_) {
        LOGW("Telemetry manager not initialized; skipping telemetry sink registration");
        return;
    }

    // Attach the telemetry manager as the C++ event router's telemetry sink.
    // The router (rac::events::route) feeds every TELEMETRY-bit event into the
    // manager via rac_telemetry_manager_track_proto and does the per-event
    // translation internally — no analytics callback needed.
    // Matches Swift: rac_events_set_telemetry_sink(mgr.ptr)
    rac_events_set_telemetry_sink(manager_);

    eventsCallbackRegistered_ = true;
    LOGI("Telemetry sink registered");
}

void TelemetryBridge::unregisterEventsCallback() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!eventsCallbackRegistered_) {
        return;
    }

    rac_events_set_telemetry_sink(nullptr);
    eventsCallbackRegistered_ = false;
    LOGI("Telemetry sink unregistered");
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
        // Development: Use Supabase from C++ dev config (development_config.cpp)
        // NO FALLBACK - credentials must come from C++ config only
        auto supabaseConfig = config::makeEndpointConfig(
            rac_dev_config_get_supabase_url() ? rac_dev_config_get_supabase_url() : "",
            rac_dev_config_get_supabase_key() ? rac_dev_config_get_supabase_key() : "");

        if (!supabaseConfig.usable) {
            LOGI("Skipping telemetry/device registration: no usable config");
            rac_telemetry_manager_http_complete(
                bridge->getHandle(),
                RAC_TRUE,
                "{}",
                nullptr
            );
            return;
        }

        baseURL = supabaseConfig.baseURL;
        apiKey = supabaseConfig.token;
        LOGD("Telemetry using configured development Supabase endpoint");
    } else {
        // Production/Staging: Use configured Railway URL
        // These come from SDK initialization (App.tsx -> RunAnywhere.initialize)
        baseURL = config::trim(InitBridge::shared().getBaseURL());

        // For production mode, prefer JWT access token (from authentication)
        // over raw API key. This matches Swift/Kotlin behavior.
        std::string accessToken = AuthBridge::shared().getAccessToken();
        if (config::isUsableSecret(accessToken)) {
            apiKey = accessToken;  // Use JWT for Authorization header
            LOGD("Telemetry using JWT access token");
        } else {
            // Fallback to API key if not authenticated yet
            apiKey = config::trim(InitBridge::shared().getApiKey());
            LOGD("Telemetry using API key (not authenticated)");
        }

        if (!config::isUsableHttpUrl(baseURL) || !config::isUsableSecret(apiKey)) {
            LOGI("Skipping telemetry/device registration: no usable config");
            rac_telemetry_manager_http_complete(
                bridge->getHandle(),
                RAC_TRUE,
                "{}",
                nullptr
            );
            return;
        }

        LOGD("Telemetry using configured production/staging endpoint");
    }

    std::string fullURL = config::appendEndpointPath(baseURL, path);

    LOGI("Telemetry POST to: %s", fullURL.c_str());

    // Use shared native C++ HTTP transport (same as device registration).
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

} // namespace bridges
} // namespace runanywhere

