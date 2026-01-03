/**
 * DeviceBridge.cpp
 *
 * C++ bridge for device operations.
 * Calls rac_device_* API from runanywhere-commons.
 */

#include "DeviceBridge.hpp"

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "DeviceBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[DeviceBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[DeviceBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

// TODO: Include RACommons headers when available
// #include <rac_device_manager.h>

namespace runanywhere {
namespace bridges {

DeviceBridge& DeviceBridge::shared() {
    static DeviceBridge instance;
    return instance;
}

std::string DeviceBridge::getDeviceId() {
    if (deviceId_.empty()) {
        // TODO: Call rac_device_get_id when RACommons is linked
        // This will read from secure storage via platform adapter
        #if 0
        const char* id = rac_device_get_id();
        if (id) {
            deviceId_ = id;
        }
        #else
        // Development stub - generate a placeholder ID
        deviceId_ = "dev-device-id";
        #endif
    }

    return deviceId_;
}

DeviceRegistrationResult DeviceBridge::registerDevice() {
    LOGI("Registering device...");

    DeviceRegistrationResult result;

    // TODO: Call rac_device_register when RACommons is linked
    #if 0
    rac_device_registration_request_t request;
    request.device_id = deviceId_.c_str();
    request.platform = "react-native";

    rac_device_registration_response_t response;
    auto status = rac_device_register(&request, &response);

    if (status == RAC_SUCCESS) {
        isRegistered_ = true;
        result.success = true;
        result.deviceId = deviceId_;
    } else {
        result.success = false;
        result.error = "Registration failed";
    }
    #else
    // Development stub
    isRegistered_ = true;
    result.success = true;
    result.deviceId = deviceId_;
    LOGI("Device registration stub - development mode");
    #endif

    return result;
}

bool DeviceBridge::isRegistered() const {
    return isRegistered_;
}

DeviceInfo DeviceBridge::getDeviceInfo() const {
    DeviceInfo info;
    info.deviceId = deviceId_;
    info.isRegistered = isRegistered_;

#if defined(__APPLE__)
    info.platform = "ios";
#else
    info.platform = "android";
#endif

    info.sdkVersion = "0.1.0";

    // TODO: Get actual device model and OS version via platform adapter

    return info;
}

void DeviceBridge::setDeviceId(const std::string& deviceId) {
    deviceId_ = deviceId;
    LOGI("Device ID set: %s", deviceId.c_str());
}

void DeviceBridge::initialize() {
    LOGI("Initializing device bridge");

    // TODO: Register callbacks with RACommons when linked
    #if 0
    rac_device_callbacks_t callbacks;
    callbacks.on_registration_complete = [](const char* deviceId, void* context) {
        auto* bridge = static_cast<DeviceBridge*>(context);
        bridge->isRegistered_ = true;
    };
    callbacks.context = this;

    rac_device_set_callbacks(&callbacks);
    #endif
}

} // namespace bridges
} // namespace runanywhere
