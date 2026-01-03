/**
 * DeviceBridge.hpp
 *
 * C++ bridge for device operations.
 * Calls rac_device_* API from runanywhere-commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Device.swift
 */

#pragma once

#include <string>
#include <functional>

namespace runanywhere {
namespace bridges {

/**
 * Device info
 */
struct DeviceInfo {
    std::string deviceId;
    std::string platform;
    std::string model;
    std::string osVersion;
    std::string sdkVersion;
    bool isRegistered;
};

/**
 * Device registration result
 */
struct DeviceRegistrationResult {
    bool success;
    std::string deviceId;
    std::string error;
};

/**
 * DeviceBridge - Device operations via rac_device_* API
 */
class DeviceBridge {
public:
    /**
     * Get shared instance
     */
    static DeviceBridge& shared();

    /**
     * Get device ID
     * @return Device ID (persisted in secure storage)
     */
    std::string getDeviceId();

    /**
     * Register device with backend
     * @return Registration result
     */
    DeviceRegistrationResult registerDevice();

    /**
     * Check if device is registered
     * @return true if registered
     */
    bool isRegistered() const;

    /**
     * Get device info
     * @return Device information
     */
    DeviceInfo getDeviceInfo() const;

    /**
     * Set device ID (typically called by platform adapter)
     * @param deviceId Device ID
     */
    void setDeviceId(const std::string& deviceId);

    /**
     * Initialize device registration callbacks
     */
    void initialize();

private:
    DeviceBridge() = default;
    ~DeviceBridge() = default;
    DeviceBridge(const DeviceBridge&) = delete;
    DeviceBridge& operator=(const DeviceBridge&) = delete;

    std::string deviceId_;
    bool isRegistered_ = false;
};

} // namespace bridges
} // namespace runanywhere
