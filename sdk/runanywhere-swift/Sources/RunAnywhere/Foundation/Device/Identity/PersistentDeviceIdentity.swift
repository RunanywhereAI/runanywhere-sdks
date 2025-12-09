//
//  PersistentDeviceIdentity.swift
//  RunAnywhere SDK
//
//  Provides persistent device UUIDs across app reinstalls
//

import Foundation
import CommonCrypto

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Device identity manager that provides persistent UUIDs across app reinstalls
public final class PersistentDeviceIdentity {

    private static let logger = SDKLogger(category: "PersistentDeviceIdentity")
    private static let keychainManager = KeychainManager.shared

    // MARK: - Device UUID

    /// Get a persistent device UUID that survives app reinstalls
    public static func getPersistentDeviceUUID() -> String {
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

    // MARK: - Device Fingerprint

    /// Get a simple device fingerprint for additional validation
    public static func getDeviceFingerprint() -> String {
        var components: [String] = []

        // Memory (doesn't change)
        let processInfo = ProcessInfo.processInfo
        components.append("mem:\(processInfo.physicalMemory)")

        // Architecture
        #if arch(arm64)
        components.append("arch:arm64")
        #elseif arch(x86_64)
        components.append("arch:x86_64")
        #else
        components.append("arch:unknown")
        #endif

        // Processor count (doesn't change)
        components.append("cores:\(processInfo.processorCount)")

        // OS major version only
        let osVersion = processInfo.operatingSystemVersion
        components.append("os:\(osVersion.majorVersion)")

        // Create fingerprint hash
        let fingerprintString = components.joined(separator: "|")
        let fingerprint = sha256(fingerprintString)

        try? keychainManager.storeDeviceFingerprint(fingerprint)

        return fingerprint
    }

    /// Validate if a device UUID is properly formatted
    public static func validateDeviceUUID(_ uuid: String) -> Bool {
        return uuid.count == 36 && uuid.contains("-")
    }

    // MARK: - Private Methods

    private static func getVendorUUID() -> String? {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    private static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
