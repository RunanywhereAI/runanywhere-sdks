/**
 * @file DeviceBridge.cpp
 * @brief C++ bridge for device operations.
 *
 * Mirrors Swift's CppBridge+Device.swift pattern.
 * Registers callbacks with rac_device_manager and delegates to platform.
 */

#include "DeviceBridge.hpp"
#include "rac_error.h"
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

// =============================================================================
// C Callback Implementations (called by RACommons)
// =============================================================================

static void deviceGetInfoCallback(rac_device_registration_info_t* outInfo, void* userData) {
    if (!outInfo || !g_deviceCallbacks || !g_deviceCallbacks->getDeviceInfo) {
        LOGE("getDeviceInfo callback not available");
        return;
    }

    DeviceInfo info = g_deviceCallbacks->getDeviceInfo();

    // Note: We need to use static storage for strings since RACommons
    // only keeps pointers. In a real implementation, these would need
    // to be managed carefully for lifetime.
    static std::string s_deviceId, s_deviceModel, s_deviceName, s_platform;
    static std::string s_osVersion, s_formFactor, s_architecture, s_chipName;
    static std::string s_gpuFamily, s_batteryState, s_deviceType, s_osName;
    static std::string s_deviceFingerprint;

    s_deviceId = info.deviceId;
    s_deviceModel = info.deviceModel;
    s_deviceName = info.deviceName;
    s_platform = info.platform;
    s_osVersion = info.osVersion;
    s_formFactor = info.formFactor;
    s_architecture = info.architecture;
    s_chipName = info.chipName;
    s_gpuFamily = info.gpuFamily;
    s_batteryState = info.batteryState;
    s_deviceType = info.formFactor; // Use formFactor as device_type
    s_osName = info.osName.empty() ? info.platform : info.osName;
    s_deviceFingerprint = info.deviceId;

    // Fill out the struct - matches Swift's implementation
    outInfo->device_id = s_deviceId.c_str();
    outInfo->device_model = s_deviceModel.c_str();
    outInfo->device_name = s_deviceName.c_str();
    outInfo->platform = s_platform.c_str();
    outInfo->os_version = s_osVersion.c_str();
    outInfo->form_factor = s_formFactor.c_str();
    outInfo->architecture = s_architecture.c_str();
    outInfo->chip_name = s_chipName.c_str();
    outInfo->total_memory = info.totalMemory;
    outInfo->available_memory = info.availableMemory;
    outInfo->has_neural_engine = info.hasNeuralEngine ? RAC_TRUE : RAC_FALSE;
    outInfo->neural_engine_cores = info.neuralEngineCores;
    outInfo->gpu_family = s_gpuFamily.c_str();
    outInfo->battery_level = info.batteryLevel;
    outInfo->battery_state = s_batteryState.empty() ? nullptr : s_batteryState.c_str();
    outInfo->is_low_power_mode = info.isLowPowerMode ? RAC_TRUE : RAC_FALSE;
    outInfo->core_count = info.coreCount;
    outInfo->performance_cores = info.performanceCores;
    outInfo->efficiency_cores = info.efficiencyCores;
    outInfo->device_fingerprint = s_deviceFingerprint.c_str();

    // Legacy fields
    outInfo->device_type = s_deviceType.c_str();
    outInfo->os_name = s_osName.c_str();
    outInfo->processor_count = info.coreCount;
    outInfo->is_simulator = info.isSimulator ? RAC_TRUE : RAC_FALSE;

    LOGD("Device info populated: model=%s, platform=%s", s_deviceModel.c_str(), s_platform.c_str());
}

static const char* deviceGetIdCallback(void* userData) {
    if (!g_deviceCallbacks || !g_deviceCallbacks->getDeviceId) {
        LOGE("getDeviceId callback not available");
        return nullptr;
    }

    static std::string s_deviceId;
    s_deviceId = g_deviceCallbacks->getDeviceId();
    return s_deviceId.c_str();
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

    LOGI("Making HTTP POST to: %s", endpoint);

    auto [success, statusCode, responseBody, errorMessage] =
        g_deviceCallbacks->httpPost(endpoint, jsonBody, requiresAuth == RAC_TRUE);

    // Store response strings statically for lifetime
    static std::string s_responseBody, s_errorMessage;
    s_responseBody = responseBody;
    s_errorMessage = errorMessage;

    if (success) {
        outResponse->result = RAC_SUCCESS;
        outResponse->status_code = statusCode;
        outResponse->response_body = s_responseBody.empty() ? nullptr : s_responseBody.c_str();
        outResponse->error_message = nullptr;
        LOGI("HTTP POST succeeded with status %d", statusCode);
        return RAC_SUCCESS;
    } else {
        outResponse->result = RAC_ERROR_NETWORK_ERROR;
        outResponse->status_code = statusCode;
        outResponse->response_body = nullptr;
        outResponse->error_message = s_errorMessage.empty() ? nullptr : s_errorMessage.c_str();
        LOGE("HTTP POST failed: %s", s_errorMessage.c_str());
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
    platformCallbacks_ = callbacks;

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

rac_result_t DeviceBridge::registerIfNeeded(rac_environment_t environment, const std::string& buildToken) {
    if (!callbacksRegistered_) {
        LOGE("Device callbacks not registered - call registerCallbacks() first");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    LOGI("Registering device if needed (env=%d)...", static_cast<int>(environment));

    const char* tokenPtr = buildToken.empty() ? nullptr : buildToken.c_str();
    rac_result_t result = rac_device_manager_register_if_needed(environment, tokenPtr);

    if (result == RAC_SUCCESS) {
        LOGI("Device registration completed successfully");
    } else {
        LOGE("Device registration failed: %d", result);
    }

    return result;
}

bool DeviceBridge::isRegistered() const {
    return rac_device_manager_is_registered() == RAC_TRUE;
}

void DeviceBridge::clearRegistration() {
    rac_device_manager_clear_registration();
    LOGI("Device registration cleared");
}

std::string DeviceBridge::getDeviceId() const {
    const char* id = rac_device_manager_get_device_id();
    return id ? std::string(id) : "";
}

} // namespace bridges
} // namespace runanywhere
