//
//  DeviceService.swift
//  RunAnywhere SDK
//
//  Core service protocol for device information and identity
//

import Foundation

/// Protocol defining device service capabilities
public protocol DeviceService {

    // MARK: - Device Identity

    /// Get a persistent device UUID that survives app reinstalls
    func getPersistentDeviceUUID() -> String

    /// Validate if a device UUID is properly formatted
    func validateDeviceUUID(_ uuid: String) -> Bool

    // MARK: - Device Fingerprint

    /// Get a simple device fingerprint for additional validation
    func getDeviceFingerprint() -> String

    // MARK: - Device Information

    /// Get current device information
    var deviceInfo: DeviceInfo { get }

    /// Get device information formatted for telemetry
    var telemetryDeviceInfo: TelemetryDeviceInfo { get }
}
