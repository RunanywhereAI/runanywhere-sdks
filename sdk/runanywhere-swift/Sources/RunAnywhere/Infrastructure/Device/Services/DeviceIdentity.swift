//
//  DeviceIdentity.swift
//  RunAnywhere SDK
//
//  Simple utility for device identity management (UUID persistence)
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Simple utility for device identity management
/// Provides persistent UUID that survives app reinstalls
public enum DeviceIdentity {

    // MARK: - Properties

    private static let logger = SDKLogger(category: "DeviceIdentity")

    // MARK: - Public API

    /// Get a persistent device UUID that survives app reinstalls
    /// Uses keychain for persistence, falls back to vendor ID or generates new UUID
    public static var persistentUUID: String {
        // Strategy 1: Try to get from keychain (survives app reinstalls)
        if let persistentUUID = KeychainManager.shared.retrieveDeviceUUID() {
            return persistentUUID
        }

        // Strategy 2: Use Apple's identifierForVendor
        if let vendorUUID = vendorUUID {
            try? KeychainManager.shared.storeDeviceUUID(vendorUUID)
            logger.debug("Stored vendor UUID in keychain")
            return vendorUUID
        }

        // Strategy 3: Generate new UUID
        let newUUID = UUID().uuidString
        try? KeychainManager.shared.storeDeviceUUID(newUUID)
        logger.debug("Generated and stored new device UUID")
        return newUUID
    }

    /// Get vendor UUID if available (iOS/tvOS only)
    private static var vendorUUID: String? {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    /// Validate if a device UUID is properly formatted
    public static func validateUUID(_ uuid: String) -> Bool {
        uuid.count == 36 && uuid.contains("-")
    }
}
