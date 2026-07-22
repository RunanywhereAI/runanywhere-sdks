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
#include "rac_sdk_state.h"         // rac_state_get_base_url (staging override)

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

struct TelemetryCallbackContext {
  rac_telemetry_manager_t *manager;
  rac_environment_t environment;
};

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

TelemetryBridge &TelemetryBridge::shared() {
  static TelemetryBridge instance;
  return instance;
}

// ============================================================================
// Lifecycle
// ============================================================================

void TelemetryBridge::initialize(rac_environment_t environment,
                                 const std::string &deviceId,
                                 const std::string &deviceModel,
                                 const std::string &osVersion,
                                 const std::string &platform,
                                 const std::string &sdkVersion) {
  rac_telemetry_manager_t *previousManager = nullptr;
  std::unique_ptr<TelemetryCallbackContext> previousContext;
  bool detachPreviousSink = false;
  {
    std::unique_lock<std::mutex> lock(mutex_);
    stateChanged_.wait(lock, [this] { return !lifecycleTransition_; });
    lifecycleTransition_ = true;
    stateChanged_.wait(lock, [this] { return activeOperations_ == 0; });
    previousManager = manager_;
    manager_ = nullptr;
    previousContext = std::move(callbackContext_);
    detachPreviousSink = eventsCallbackRegistered_;
    eventsCallbackRegistered_ = false;
  }

  if (detachPreviousSink) {
    rac_events_set_telemetry_sink(nullptr);
  }
  if (previousManager) {
    rac_telemetry_manager_flush(previousManager);
    rac_telemetry_manager_destroy(previousManager);
  }

  const std::string telemetryPlatform = platform.empty() ? "unknown" : platform;

  // Create telemetry manager
  // Matches Swift: rac_telemetry_manager_create(Environment.toC(environment),
  // did, plat, ver)
  rac_telemetry_manager_t *manager = rac_telemetry_manager_create(
      environment, deviceId.c_str(), telemetryPlatform.c_str(),
      sdkVersion.c_str());

  std::unique_ptr<TelemetryCallbackContext> context;
  if (!manager) {
    LOGE("Failed to create telemetry manager");
  } else {
    context = std::make_unique<TelemetryCallbackContext>(
        TelemetryCallbackContext{manager, environment});

    // Set device info
    // Matches Swift: rac_telemetry_manager_set_device_info(manager, model,
    // os)
    rac_telemetry_manager_set_device_info(manager, deviceModel.c_str(),
                                          osVersion.c_str());

    // Register HTTP callback - this is where platform provides HTTP transport
    // Matches Swift: rac_telemetry_manager_set_http_callback(manager,
    // telemetryHttpCallback, userData)
    rac_telemetry_manager_set_http_callback(manager, telemetryHttpCallback,
                                            context.get());
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    manager_ = manager;
    callbackContext_ = std::move(context);
    lifecycleTransition_ = false;
  }
  stateChanged_.notify_all();

  if (manager) {
    LOGI("Telemetry manager initialized successfully");
  }
}

void TelemetryBridge::shutdown() {
  rac_telemetry_manager_t *manager = nullptr;
  std::unique_ptr<TelemetryCallbackContext> context;
  bool detachSink = false;
  {
    std::unique_lock<std::mutex> lock(mutex_);
    stateChanged_.wait(lock, [this] { return !lifecycleTransition_; });
    lifecycleTransition_ = true;
    stateChanged_.wait(lock, [this] { return activeOperations_ == 0; });
    manager = manager_;
    manager_ = nullptr;
    context = std::move(callbackContext_);
    detachSink = eventsCallbackRegistered_;
    eventsCallbackRegistered_ = false;
  }

  // Stop new routed events before flushing/destroying the snapshotted
  // manager. The callback context remains alive until both calls return.
  if (detachSink) {
    rac_events_set_telemetry_sink(nullptr);
  }

  if (manager) {
    LOGI("Shutting down telemetry manager...");
    rac_telemetry_manager_flush(manager);
    rac_telemetry_manager_destroy(manager);
    LOGI("Telemetry manager destroyed");
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    lifecycleTransition_ = false;
  }
  stateChanged_.notify_all();
}

bool TelemetryBridge::isInitialized() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return manager_ != nullptr;
}

// ============================================================================
// Event Tracking
// ============================================================================

void TelemetryBridge::flush() {
  rac_telemetry_manager_t *manager = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!manager_ || lifecycleTransition_) {
      return;
    }
    manager = manager_;
    ++activeOperations_;
  }

  LOGI("Flushing telemetry events...");
  rac_telemetry_manager_flush(manager);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    --activeOperations_;
  }
  stateChanged_.notify_all();
}

// ============================================================================
// Events Callback Registration
// ============================================================================

void TelemetryBridge::registerEventsCallback() {
  rac_telemetry_manager_t *manager = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (eventsCallbackRegistered_) {
      return;
    }
    if (!manager_ || lifecycleTransition_) {
      LOGW("Telemetry manager not initialized; skipping telemetry sink "
           "registration");
      return;
    }
    manager = manager_;
    ++activeOperations_;
  }

  // Attach the telemetry manager as the C++ event router's telemetry sink.
  // The router (rac::events::route) feeds every TELEMETRY-bit event into the
  // manager via rac_telemetry_manager_track_proto and does the per-event
  // translation internally — no analytics callback needed.
  // Matches Swift: rac_events_set_telemetry_sink(mgr.ptr)
  rac_events_set_telemetry_sink(manager);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    eventsCallbackRegistered_ = true;
    --activeOperations_;
  }
  stateChanged_.notify_all();
  LOGI("Telemetry sink registered");
}

void TelemetryBridge::unregisterEventsCallback() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!eventsCallbackRegistered_ || lifecycleTransition_) {
      return;
    }
    ++activeOperations_;
  }

  rac_events_set_telemetry_sink(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    eventsCallbackRegistered_ = false;
    --activeOperations_;
  }
  stateChanged_.notify_all();
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
static void telemetryHttpCallback(void *userData, const char *endpoint,
                                  const char *jsonBody, size_t jsonLength,
                                  rac_bool_t requiresAuth) {
  if (!endpoint || !jsonBody) {
    LOGE("Invalid telemetry HTTP callback parameters");
    return;
  }

  auto *context = static_cast<TelemetryCallbackContext *>(userData);
  if (!context || !context->manager) {
    LOGE("Telemetry callback context not available");
    return;
  }

  std::string path(endpoint);
  std::string json(jsonBody, jsonLength);
  const rac_environment_t env = context->environment;
  rac_telemetry_manager_t *manager = context->manager;

  LOGI("Telemetry HTTP callback: bodyLen=%zu, env=%d", jsonLength, env);

  // Build full URL based on environment
  // Matches Swift HTTPService logic
  std::string baseURL;
  std::string apiKey;

  {
    // Effective config from commons state, for every environment: staging
    // overrides whatever the app passed (baked URL, keyless), dev/prod use the
    // effective URL falling back to the SDK-initialization value. There is no
    // direct-to-datastore path — the backend is always reached through this URL.
    const char *stateURL = rac_state_get_base_url();
    baseURL = (stateURL != nullptr && stateURL[0] != '\0')
                  ? config::trim(stateURL)
                  : config::trim(InitBridge::shared().getBaseURL());

    // For production mode, prefer JWT access token (from authentication)
    // over raw API key. This matches Swift/Kotlin behavior.
    std::string accessToken = AuthBridge::shared().getAccessToken();
    if (config::isUsableSecret(accessToken)) {
      apiKey = accessToken; // Use JWT for Authorization header
      LOGD("Telemetry using JWT access token");
    } else {
      // Fall back to the commons-state key. Staging clears it (keyless):
      // the POST goes out with no Authorization header and the backend
      // attributes it to the PUBLIC org — a stale app key would 401.
      const char *stateKey = rac_state_get_api_key();
      apiKey = config::trim(stateKey != nullptr ? stateKey : "");
      LOGD("Telemetry using %s (not authenticated)",
           apiKey.empty() ? "keyless mode" : "API key");
    }

    // Keyless staging is valid: the request goes out unauthenticated and
    // the backend attributes it to the PUBLIC org. Only a usable URL is
    // mandatory.
    if (!config::isUsableHttpUrl(baseURL)) {
      LOGI("Skipping telemetry/device registration: no usable config");
      rac_telemetry_manager_http_complete(manager, RAC_TRUE, "{}", nullptr);
      return;
    }
    if (!config::isUsableSecret(apiKey)) {
      apiKey.clear();
    }

    LOGD("Telemetry using configured production/staging endpoint");
  }

  std::string fullURL = config::appendEndpointPath(baseURL, path);

  LOGI("Telemetry POST starting");

  // Use shared native C++ HTTP transport (same as device registration).
  auto [success, statusCode, responseBody, errorMessage] =
      InitBridge::shared().httpPostSync(fullURL, json, apiKey);
  (void)errorMessage;

  if (success) {
    LOGI("Telemetry sent successfully (status=%d)", statusCode);

    // Notify C++ that HTTP completed
    rac_telemetry_manager_http_complete(manager, RAC_TRUE, responseBody.c_str(),
                                        nullptr);
  } else {
    LOGE("Telemetry HTTP failed (status=%d)", statusCode);

    // Notify C++ of failure
    rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                        "Telemetry HTTP request failed");
  }
}

} // namespace bridges
} // namespace runanywhere
