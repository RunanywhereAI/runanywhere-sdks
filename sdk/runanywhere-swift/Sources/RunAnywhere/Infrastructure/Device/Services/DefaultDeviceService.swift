//
//  DefaultDeviceService.swift
//  RunAnywhere SDK
//
//  Default implementation of DeviceService providing device identity and information
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Default implementation of DeviceService
/// Provides persistent device identity and device information
public final class DefaultDeviceService: DeviceService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DefaultDeviceService")
    private let keychainManager: KeychainManager

    // MARK: - Initialization

    public init(keychainManager: KeychainManager = .shared) {
        self.keychainManager = keychainManager
        logger.debug("DefaultDeviceService initialized")
    }

    // MARK: - DeviceService Implementation

    /// Get a persistent device UUID that survives app reinstalls
    public func getPersistentDeviceUUID() -> String {
        logger.debug("Attempting to retrieve persistent device UUID")

        // Strategy 1: Try to get from keychain (survives app reinstalls)
        if let persistentUUID = keychainManager.retrieveDeviceUUID() {
            logger.info("Retrieved device UUID from keychain")
            return persistentUUID
        }

        // Strategy 2: Use Apple's identifierForVendor
        if let vendorUUID = getVendorUUID() {
            logger.info("Retrieved device UUID from vendor identifier")
            try? keychainManager.storeDeviceUUID(vendorUUID)
            return vendorUUID
        }

        // Strategy 3: Generate new UUID
        let newUUID = UUID().uuidString
        try? keychainManager.storeDeviceUUID(newUUID)
        logger.info("Generated new device UUID")
        return newUUID
    }

    /// Validate if a device UUID is properly formatted
    public func validateDeviceUUID(_ uuid: String) -> Bool {
        return uuid.count == 36 && uuid.contains("-")
    }

    /// Get a simple device fingerprint for additional validation
    public func getDeviceFingerprint() -> String {
        let fingerprint = DeviceFingerprintUtility.generateFingerprint()
        try? keychainManager.storeDeviceFingerprint(fingerprint)
        return fingerprint
    }

    /// Get current device information
    public var deviceInfo: DeviceInfo {
        return DeviceInfo.current
    }

    /// Get device information formatted for telemetry
    public var telemetryDeviceInfo: TelemetryDeviceInfo {
        return TelemetryDeviceInfo.current
    }

    // MARK: - Private Methods

    private func getVendorUUID() -> String? {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }
}
