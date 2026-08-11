/**
 * @file DeviceBridge.cpp
 * @brief C++ bridge for device operations.
 *
 * Mirrors Swift's CppBridge+Device.swift pattern.
 * Registers callbacks with rac_device_manager and delegates to platform.
 */

#include "DeviceBridge.hpp"
#include "rac_error.h"
#include <cstddef>
#include <cstring>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "DeviceBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[DeviceBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[DeviceBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[DeviceBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// Static storage for callbacks (needed for C function pointers)
// =============================================================================

static DevicePlatformCallbacks* g_deviceCallbacks = nullptr;

static void wipeAndClear(std::string &value) {
  volatile char *bytes = value.empty() ? nullptr : value.data();
  for (std::size_t i = 0; i < value.size(); ++i) {
    bytes[i] = '\0';
  }
  value.clear();
}

struct DeviceCallbackStrings {
  std::string deviceId;
  std::string deviceModel;
  std::string deviceName;
  std::string platform;
  std::string osVersion;
  std::string formFactor;
  std::string architecture;
  std::string chipName;
  std::string gpuFamily;
  std::string batteryState;
  std::string deviceFingerprint;
  std::string responseBody;
  std::string errorMessage;

  void clear() {
    wipeAndClear(deviceId);
    wipeAndClear(deviceModel);
    wipeAndClear(deviceName);
    wipeAndClear(platform);
    wipeAndClear(osVersion);
    wipeAndClear(formFactor);
    wipeAndClear(architecture);
    wipeAndClear(chipName);
    wipeAndClear(gpuFamily);
    wipeAndClear(batteryState);
    wipeAndClear(deviceFingerprint);
    wipeAndClear(responseBody);
    wipeAndClear(errorMessage);
  }
};

static DeviceCallbackStrings g_deviceCallbackStrings;

// =============================================================================
// C Callback Implementations (called by RACommons)
// =============================================================================

static void deviceGetInfoCallback(rac_device_registration_info_t* outInfo, void* userData) {
    if (!outInfo || !g_deviceCallbacks || !g_deviceCallbacks->getDeviceInfo) {
        LOGE("getDeviceInfo callback not available");
        return;
    }

    DeviceInfo info = g_deviceCallbacks->getDeviceInfo();

    // Commons consumes these pointers synchronously while holding the device
    // manager lock. Process-local storage keeps them valid for that call and
    // is cleared when the callbacks are unregistered.
    g_deviceCallbackStrings.deviceId = info.deviceId;
    g_deviceCallbackStrings.deviceModel = info.deviceModel;
    g_deviceCallbackStrings.deviceName = info.deviceName;
    g_deviceCallbackStrings.platform = info.platform;
    g_deviceCallbackStrings.osVersion = info.osVersion;
    g_deviceCallbackStrings.formFactor = info.formFactor;
    g_deviceCallbackStrings.architecture = info.architecture;
    g_deviceCallbackStrings.chipName = info.chipName;
    g_deviceCallbackStrings.gpuFamily = info.gpuFamily;
    g_deviceCallbackStrings.batteryState = info.batteryState;
    g_deviceCallbackStrings.deviceFingerprint =
        info.deviceFingerprint.empty() ? info.deviceId : info.deviceFingerprint;

    // Fill out the struct - matches Swift's implementation
    outInfo->device_id = g_deviceCallbackStrings.deviceId.c_str();
    outInfo->device_model = g_deviceCallbackStrings.deviceModel.c_str();
    outInfo->device_name = g_deviceCallbackStrings.deviceName.c_str();
    outInfo->platform = g_deviceCallbackStrings.platform.c_str();
    outInfo->os_version = g_deviceCallbackStrings.osVersion.c_str();
    outInfo->form_factor = g_deviceCallbackStrings.formFactor.c_str();
    outInfo->architecture = g_deviceCallbackStrings.architecture.c_str();
    outInfo->chip_name = g_deviceCallbackStrings.chipName.c_str();
    outInfo->total_memory = info.totalMemory;
    outInfo->available_memory = info.availableMemory;
    outInfo->has_neural_engine = info.hasNeuralEngine ? RAC_TRUE : RAC_FALSE;
    outInfo->neural_engine_cores = info.neuralEngineCores;
    outInfo->gpu_family = g_deviceCallbackStrings.gpuFamily.c_str();
    outInfo->battery_level = info.batteryLevel;
    outInfo->battery_state = g_deviceCallbackStrings.batteryState.empty()
                                 ? nullptr
                                 : g_deviceCallbackStrings.batteryState.c_str();
    outInfo->is_low_power_mode = info.isLowPowerMode ? RAC_TRUE : RAC_FALSE;
    outInfo->core_count = info.coreCount;
    outInfo->performance_cores = info.performanceCores;
    outInfo->efficiency_cores = info.efficiencyCores;
    outInfo->device_fingerprint =
        g_deviceCallbackStrings.deviceFingerprint.c_str();

    LOGD("Device info populated: model=%s, platform=%s",
         g_deviceCallbackStrings.deviceModel.c_str(),
         g_deviceCallbackStrings.platform.c_str());
}

static const char* deviceGetIdCallback(void* userData) {
    if (!g_deviceCallbacks || !g_deviceCallbacks->getDeviceId) {
        LOGE("getDeviceId callback not available");
        return nullptr;
    }

    g_deviceCallbackStrings.deviceId = g_deviceCallbacks->getDeviceId();
    return g_deviceCallbackStrings.deviceId.c_str();
}

static rac_bool_t deviceIsRegisteredCallback(void* userData) {
    if (!g_deviceCallbacks || !g_deviceCallbacks->isRegistered) {
        return RAC_FALSE;
    }
    return g_deviceCallbacks->isRegistered() ? RAC_TRUE : RAC_FALSE;
}

static void deviceSetRegisteredCallback(rac_bool_t registered, void* userData) {
    if (!g_deviceCallbacks || !g_deviceCallbacks->setRegistered) {
        LOGE("setRegistered callback not available");
        return;
    }
    g_deviceCallbacks->setRegistered(registered == RAC_TRUE);
    LOGI("Device registration status set: %s", registered == RAC_TRUE ? "true" : "false");
}

static rac_result_t deviceHttpPostCallback(
    const char* endpoint,
    const char* jsonBody,
    rac_bool_t requiresAuth,
    rac_device_http_response_t* outResponse,
    void* userData
) {
    if (!endpoint || !jsonBody || !outResponse) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!g_deviceCallbacks || !g_deviceCallbacks->httpPost) {
        LOGE("httpPost callback not available");
        outResponse->result = RAC_ERROR_NOT_SUPPORTED;
        return RAC_ERROR_NOT_SUPPORTED;
    }

    LOGI("Device HTTP POST starting");

    auto [success, statusCode, responseBody, errorMessage] =
        g_deviceCallbacks->httpPost(endpoint, jsonBody, requiresAuth == RAC_TRUE);

    g_deviceCallbackStrings.responseBody = responseBody;
    g_deviceCallbackStrings.errorMessage = errorMessage;

    if (success) {
        outResponse->result = RAC_SUCCESS;
        outResponse->status_code = statusCode;
        outResponse->response_body =
            g_deviceCallbackStrings.responseBody.empty()
                ? nullptr
                : g_deviceCallbackStrings.responseBody.c_str();
        outResponse->error_message = nullptr;
        LOGI("HTTP POST succeeded with status %d", statusCode);
        return RAC_SUCCESS;
    } else {
        outResponse->result = RAC_ERROR_NETWORK_ERROR;
        outResponse->status_code = statusCode;
        outResponse->response_body = nullptr;
        outResponse->error_message =
            g_deviceCallbackStrings.errorMessage.empty()
                ? nullptr
                : g_deviceCallbackStrings.errorMessage.c_str();
        LOGE("HTTP POST failed");
        return RAC_ERROR_NETWORK_ERROR;
    }
}

// =============================================================================
// DeviceBridge Implementation
// =============================================================================

DeviceBridge& DeviceBridge::shared() {
    static DeviceBridge instance;
    return instance;
}

void DeviceBridge::setPlatformCallbacks(const DevicePlatformCallbacks& callbacks) {
  {
    std::lock_guard<std::mutex> lock(platformCallbacksMutex_);
    platformCallbacks_ = callbacks;
  }

    // Store in global for C callbacks
    static DevicePlatformCallbacks storedCallbacks;
    storedCallbacks = callbacks;
    g_deviceCallbacks = &storedCallbacks;

    LOGI("Device platform callbacks set");
}

rac_result_t DeviceBridge::registerCallbacks() {
    if (callbacksRegistered_) {
        LOGD("Device callbacks already registered");
        return RAC_SUCCESS;
    }

    // Reset callbacks struct
    memset(&racCallbacks_, 0, sizeof(racCallbacks_));

    // Set callback function pointers
    racCallbacks_.get_device_info = deviceGetInfoCallback;
    racCallbacks_.get_device_id = deviceGetIdCallback;
    racCallbacks_.is_registered = deviceIsRegisteredCallback;
    racCallbacks_.set_registered = deviceSetRegisteredCallback;
    racCallbacks_.http_post = deviceHttpPostCallback;
    racCallbacks_.user_data = nullptr;

    // Register with RACommons
    rac_result_t result = rac_device_manager_set_callbacks(&racCallbacks_);

    if (result == RAC_SUCCESS) {
        callbacksRegistered_ = true;
        LOGI("Device manager callbacks registered with RACommons");
    } else {
        LOGE("Failed to register device manager callbacks: %d", result);
    }

    return result;
}

void DeviceBridge::unregisterCallbacks() {
  // Commons takes the device-manager lock, so no callback can still be
  // using the process-local strings when this returns.
  rac_device_manager_clear_callbacks();
  callbacksRegistered_ = false;
  g_deviceCallbacks = nullptr;
  g_deviceCallbackStrings.clear();
  memset(&racCallbacks_, 0, sizeof(racCallbacks_));
  {
    std::lock_guard<std::mutex> lock(platformCallbacksMutex_);
    platformCallbacks_ = {};
  }
  LOGI("Device manager callbacks unregistered");
}

bool DeviceBridge::isRegistered() const {
    return rac_device_manager_is_registered() == RAC_TRUE;
}

std::string DeviceBridge::getDeviceId() const {
  std::lock_guard<std::mutex> lock(platformCallbacksMutex_);
  if (!platformCallbacks_.getDeviceId) {
    return "";
  }
  return platformCallbacks_.getDeviceId();
}

DeviceInfo DeviceBridge::getDeviceInfo() const {
  std::lock_guard<std::mutex> lock(platformCallbacksMutex_);
  if (!platformCallbacks_.getDeviceInfo) {
    LOGE("getDeviceInfo callback not available");
    return DeviceInfo{};
  }

  DeviceInfo info = platformCallbacks_.getDeviceInfo();
  LOGD("Device info retrieved: availableMemory=%lld bytes",
       static_cast<long long>(info.availableMemory));
  return info;
}

} // namespace bridges
} // namespace runanywhere
