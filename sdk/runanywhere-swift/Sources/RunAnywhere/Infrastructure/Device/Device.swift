//
//  Device.swift
//  RunAnywhere SDK
//
//  Public entry point for the Device capability
//

import Foundation

/// Public entry point for the Device capability
/// Provides simplified access to device identity and information
public final class Device {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Device()

    // MARK: - Properties

    private let deviceService: DeviceService
    private let logger = SDKLogger(category: "Device")

    // MARK: - Initialization

    /// Initialize with default service
    public convenience init() {
        let service = DefaultDeviceService()
        self.init(deviceService: service)
    }

    /// Initialize with custom service (for testing or customization)
    /// - Parameter deviceService: The service to use
    internal init(deviceService: DeviceService) {
        self.deviceService = deviceService
        logger.debug("Device initialized")
    }

    // MARK: - Public API

    /// Access the underlying service
    /// Provides low-level operations if needed
    public var service: DeviceService {
        return deviceService
    }

    // MARK: - Device Identity (Convenience Methods)

    /// Get a persistent device UUID that survives app reinstalls
    public var persistentUUID: String {
        return deviceService.getPersistentDeviceUUID()
    }

    /// Validate if a device UUID is properly formatted
    /// - Parameter uuid: The UUID to validate
    /// - Returns: True if the UUID is valid
    public func validateUUID(_ uuid: String) -> Bool {
        return deviceService.validateDeviceUUID(uuid)
    }

    /// Get a simple device fingerprint for additional validation
    public var fingerprint: String {
        return deviceService.getDeviceFingerprint()
    }

    // MARK: - Device Information (Convenience Methods)

    /// Get current device information
    public var info: DeviceInfo {
        return deviceService.deviceInfo
    }

    /// Get device information formatted for telemetry
    public var telemetryInfo: TelemetryDeviceInfo {
        return deviceService.telemetryDeviceInfo
    }

    // MARK: - Static Convenience Methods

    /// Get a persistent device UUID (static convenience)
    public static func getPersistentDeviceUUID() -> String {
        return shared.persistentUUID
    }
}
