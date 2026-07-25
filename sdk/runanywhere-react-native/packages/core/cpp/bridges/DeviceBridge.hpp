/**
 * @file DeviceBridge.hpp
 * @brief C++ bridge for device operations.
 *
 * Mirrors Swift's CppBridge+Device.swift pattern.
 * Registers callbacks with rac_device_manager and delegates to platform.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Device.swift
 */

#pragma once

#include <functional>
#include <mutex>
#include <string>

#include "rac_types.h"
#include "rac_device_manager.h"
#include "rac_environment.h"

namespace runanywhere {
namespace bridges {

/**
 * Device info structure
 */
struct DeviceInfo {
    std::string deviceId;
    std::string deviceModel;
    std::string deviceName;
    std::string platform;
    std::string osName;
    std::string osVersion;
    std::string formFactor;
    std::string architecture;
    std::string chipName;
    int64_t totalMemory = 0;
    int64_t availableMemory = 0;
    bool hasNeuralEngine = false;
    int32_t neuralEngineCores = 0;
    std::string gpuFamily;
    float batteryLevel = -1.0f;
    std::string batteryState;
    bool isLowPowerMode = false;
    int32_t coreCount = 0;
    int32_t performanceCores = 0;
    int32_t efficiencyCores = 0;
    bool isSimulator = false;
    std::string sdkVersion;
    std::string deviceFingerprint;
};

/**
 * Device registration result
 */
struct DeviceRegistrationResult {
    bool success = false;
    std::string deviceId;
    std::string error;
};



/**
 * Platform callbacks for device operations
 */
struct DevicePlatformCallbacks {
    // Get device hardware/OS info
    std::function<DeviceInfo()> getDeviceInfo;

    // Get persistent device ID (from keychain/keystore)
    std::function<std::string()> getDeviceId;

    // Check if device is registered (from UserDefaults/SharedPrefs)
    std::function<bool()> isRegistered;

    // Set registration status
    std::function<void(bool)> setRegistered;

    // Make HTTP POST for device registration
    // Returns: (success, statusCode, responseBody, errorMessage)
    std::function<std::tuple<bool, int, std::string, std::string>(
        const std::string& endpoint,
        const std::string& jsonBody,
        bool requiresAuth
    )> httpPost;
};

/**
 * DeviceBridge - Device registration and info via rac_device_manager_* API
 *
 * Mirrors Swift's CppBridge.Device pattern:
 * - Platform provides callbacks
 * - C++ handles business logic via RACommons
 */
class DeviceBridge {
public:
    /**
     * Get shared instance
     */
    static DeviceBridge& shared();

    /**
     * Set platform callbacks
     * Must be called during SDK initialization BEFORE registerCallbacks()
     */
    void setPlatformCallbacks(const DevicePlatformCallbacks& callbacks);

    /**
     * Register callbacks with RACommons device manager
     * Must be called during SDK initialization after setPlatformCallbacks()
     */
    rac_result_t registerCallbacks();

    /**
     * Unregister callbacks and clear process-local callback state.
     * Durable device identity and registration values remain in secure storage.
     */
    void unregisterCallbacks();

    /**
     * Check if device is registered
     */
    bool isRegistered() const;

    /**
     * Get the device ID
     */
    std::string getDeviceId() const;

    /**
     * Get device info
     */
    DeviceInfo getDeviceInfo() const;



    /**
     * Check if callbacks are registered
     */
    bool isCallbacksRegistered() const { return callbacksRegistered_; }

private:
    DeviceBridge() = default;
    ~DeviceBridge() = default;
    DeviceBridge(const DeviceBridge&) = delete;
    DeviceBridge& operator=(const DeviceBridge&) = delete;

    bool callbacksRegistered_ = false;
    mutable std::mutex platformCallbacksMutex_;
    DevicePlatformCallbacks platformCallbacks_{};

    // Callbacks struct for RACommons (must persist)
    rac_device_callbacks_t racCallbacks_{};
};

} // namespace bridges
} // namespace runanywhere
