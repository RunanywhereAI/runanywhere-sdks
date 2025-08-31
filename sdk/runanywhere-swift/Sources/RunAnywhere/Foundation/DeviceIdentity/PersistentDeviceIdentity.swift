import Foundation
import Security
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Comprehensive device identity manager that provides persistent UUIDs across app reinstalls
/// Uses multiple fallback mechanisms to ensure device identification persistence
public class PersistentDeviceIdentity {

    private static let logger = SDKLogger(category: "PersistentDeviceIdentity")

    // Keychain configuration for persistent storage
    private static let keychainService = "com.runanywhere.sdk.device"
    private static let deviceUUIDKey = "persistent_device_uuid"
    private static let accessGroup = "$(AppIdentifierPrefix)com.runanywhere.shared" // Requires entitlements

    /// Get a persistent device UUID that survives app reinstalls
    /// Uses a multi-layered approach for maximum persistence
    public static func getPersistentDeviceUUID() -> String {
        logger.debug("Attempting to retrieve persistent device UUID")

        // Strategy 1: Try to get from persistent keychain (survives app reinstalls)
        if let persistentUUID = getPersistentKeychainUUID() {
            logger.info("Retrieved device UUID from persistent keychain")
            return persistentUUID
        }

        // Strategy 2: Use Apple's identifierForVendor (stable but can change)
        if let vendorUUID = getVendorBasedUUID() {
            logger.info("Retrieved device UUID from vendor identifier")
            // Store this in persistent keychain for future use
            storePersistentKeychainUUID(vendorUUID)
            return vendorUUID
        }

        // Strategy 3: Generate new UUID and store persistently
        let newUUID = generateAndStoreNewUUID()
        logger.info("Generated new device UUID")
        return newUUID
    }

    /// Get device fingerprint for additional validation
    /// This provides device characteristics that can help verify identity
    public static func getDeviceFingerprint() -> String {
        var components: [String] = []

        // Hardware characteristics (these don't change)
        let processInfo = ProcessInfo.processInfo
        components.append("mem:\(processInfo.physicalMemory)")

        #if arch(arm64)
        components.append("arch:arm64")
        #elseif arch(x86_64)
        components.append("arch:x86_64")
        #else
        components.append("arch:unknown")
        #endif

        // Use DeviceKitAdapter if available for chip info
        let adapter = DeviceKitAdapter()
        let processorInfo = adapter.getProcessorInfo()
        components.append("chip:\(processorInfo.chipName)")
        components.append("cores:\(processorInfo.coreCount)")

        // OS info (major version only, as minor versions change)
        let osVersion = processInfo.operatingSystemVersion
        components.append("os:\(osVersion.majorVersion)")

        // Create fingerprint hash
        let fingerprintString = components.joined(separator:"|")
        return sha256(fingerprintString)
    }

    /// Validate if a device UUID still represents the same physical device
    public static func validateDeviceUUID(_ uuid: String) -> Bool {
        // For now, we trust any UUID that's properly formatted
        // In the future, this could compare against device fingerprints
        return uuid.count == 36 && uuid.contains("-")
    }

    // MARK: - Private Methods

    /// Get UUID from persistent keychain (survives app reinstalls)
    private static func getPersistentKeychainUUID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: deviceUUIDKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Key setting for persistence across app reinstalls
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let uuid = String(data: data, encoding: .utf8) else {
            logger.debug("No persistent keychain UUID found")
            return nil
        }

        return uuid
    }

    /// Store UUID in persistent keychain
    private static func storePersistentKeychainUUID(_ uuid: String) {
        guard let data = uuid.data(using: .utf8) else { return }

        // First, delete any existing entry
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: deviceUUIDKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry with persistent settings
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: deviceUUIDKey,
            kSecValueData as String: data,
            // Critical: This setting allows keychain item to survive app uninstalls
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            // Optional: Use access group for sharing across apps (requires entitlements)
            // kSecAttrAccessGroup as String: accessGroup
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            logger.debug("Successfully stored device UUID in persistent keychain")
        } else {
            logger.warning("Failed to store device UUID in keychain: \(status)")
        }
    }

    /// Get vendor-based UUID (Apple's recommended approach)
    private static func getVendorBasedUUID() -> String? {
        #if os(iOS) || os(tvOS)
        // identifierForVendor is stable as long as at least one app from the vendor is installed
        let vendorId = UIDevice.current.identifierForVendor?.uuidString
        if let vendorId = vendorId {
            logger.debug("Retrieved vendor identifier: \(vendorId)")
            return vendorId
        }
        #endif

        #if os(macOS)
        // On macOS, we can use system hardware UUID (requires elevated permissions)
        // For now, we'll skip this as it requires special entitlements
        #endif

        return nil
    }

    /// Generate and store a completely new UUID
    private static func generateAndStoreNewUUID() -> String {
        let newUUID = UUID().uuidString
        storePersistentKeychainUUID(newUUID)
        return newUUID
    }

    /// Create SHA256 hash of a string
    private static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Import CommonCrypto (for SHA256)
#if os(iOS) || os(tvOS) || os(watchOS)
import CommonCrypto
#elseif os(macOS)
import CommonCrypto
#endif
