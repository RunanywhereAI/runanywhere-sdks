import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Device identity management
/// Handles device ID persistence and registration state
public class DeviceManager {

    private static let deviceIdKey = "com.runanywhere.sdk.deviceId"
    private static let registrationStateKey = "com.runanywhere.sdk.registrationState"

    private static let lock = UnfairLock()

    // MARK: - Device ID Management

    /// Get stored device ID from local persistence
    /// - Returns: Device ID if exists, nil otherwise
    public static func getStoredDeviceId() -> String? {
        return lock.withLock {
            // Try keychain first (production), then UserDefaults (development)
            if let keychainId = try? KeychainManager.shared.getDeviceId() {
                return keychainId
            }

            // Fallback to UserDefaults for development
            return UserDefaults.standard.string(forKey: deviceIdKey)
        }
    }

    /// Store device ID in local persistence
    /// - Parameter deviceId: Device ID to store
    /// - Throws: Storage error if unable to persist
    public static func storeDeviceId(_ deviceId: String) throws {
        try lock.withLock {
            guard !deviceId.isEmpty else {
                throw SDKError.validationFailed("Device ID cannot be empty")
            }

            // Store in keychain for production environments
            if let environment = RunAnywhere.currentEnvironment,
               environment != .development {
                try KeychainManager.shared.storeDeviceId(deviceId)
            }

            // Always store in UserDefaults as fallback
            UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
            UserDefaults.standard.synchronize()

            // Mark as registered
            setRegistrationState(.registered)

            let logger = SDKLogger(category: "DeviceManager")
            logger.debug("Device ID stored: \(deviceId.prefix(8))...")
        }
    }

    /// Clear stored device ID (for testing or reset)
    public static func clearDeviceId() {
        lock.withLock {
            // Clear from keychain
            try? KeychainManager.shared.clearDeviceId()

            // Clear from UserDefaults
            UserDefaults.standard.removeObject(forKey: deviceIdKey)
            UserDefaults.standard.removeObject(forKey: registrationStateKey)
            UserDefaults.standard.synchronize()

            let logger = SDKLogger(category: "DeviceManager")
            logger.debug("Device ID cleared")
        }
    }

    // MARK: - Registration State

    public enum RegistrationState: String, CaseIterable {
        case notRegistered = "not_registered"
        case registering = "registering"
        case registered = "registered"
        case failed = "failed"
    }

    /// Check if device is registered
    /// - Returns: true if device has been registered
    public static func isDeviceRegistered() -> Bool {
        return lock.withLock {
            let state = getRegistrationState()
            return state == .registered && getStoredDeviceId() != nil
        }
    }

    /// Get current registration state
    /// - Returns: Current registration state
    public static func getRegistrationState() -> RegistrationState {
        let stateString = UserDefaults.standard.string(forKey: registrationStateKey) ?? RegistrationState.notRegistered.rawValue
        return RegistrationState(rawValue: stateString) ?? .notRegistered
    }

    /// Set registration state
    /// - Parameter state: New registration state
    public static func setRegistrationState(_ state: RegistrationState) {
        UserDefaults.standard.set(state.rawValue, forKey: registrationStateKey)
        UserDefaults.standard.synchronize()

        let logger = SDKLogger(category: "DeviceManager")
        logger.debug("Registration state changed to: \(state.rawValue)")
    }

    // MARK: - Device Registration Logic

    /// Generate a unique device identifier
    /// Uses identifierForVendor on iOS, or creates a UUID as fallback
    /// - Returns: Unique device identifier
    public static func generateDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif

        // Fallback to random UUID
        return UUID().uuidString
    }

    /// Create device info for registration
    /// - Returns: Device information dictionary
    static func createDeviceInfo() -> [String: Any] {
        var deviceInfo: [String: Any] = [:]

        #if os(iOS)
        deviceInfo["platform"] = "iOS"
        deviceInfo["model"] = UIDevice.current.model
        deviceInfo["systemVersion"] = UIDevice.current.systemVersion
        deviceInfo["name"] = UIDevice.current.name
        #elseif os(macOS)
        deviceInfo["platform"] = "macOS"
        let processInfo = ProcessInfo.processInfo
        deviceInfo["systemVersion"] = processInfo.operatingSystemVersionString
        deviceInfo["hostName"] = processInfo.hostName
        #elseif os(tvOS)
        deviceInfo["platform"] = "tvOS"
        deviceInfo["model"] = UIDevice.current.model
        deviceInfo["systemVersion"] = UIDevice.current.systemVersion
        #elseif os(watchOS)
        deviceInfo["platform"] = "watchOS"
        deviceInfo["model"] = WKInterfaceDevice.current().model
        deviceInfo["systemVersion"] = WKInterfaceDevice.current().systemVersion
        #else
        deviceInfo["platform"] = "Unknown"
        #endif

        // Add SDK info
        deviceInfo["sdkVersion"] = "1.0.0" // TODO: Get from build config
        deviceInfo["registrationTimestamp"] = Date().timeIntervalSince1970

        return deviceInfo
    }
}

// MARK: - KeychainManager Extensions

extension KeychainManager {
    private static let deviceIdKey = "com.runanywhere.sdk.deviceId"

    /// Get device ID from keychain
    /// - Returns: Device ID if exists
    func getDeviceId() throws -> String? {
        do {
            return try retrieve(for: Self.deviceIdKey)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    /// Store device ID in keychain
    /// - Parameter deviceId: Device ID to store
    func storeDeviceId(_ deviceId: String) throws {
        try store(deviceId, for: Self.deviceIdKey)
    }

    /// Clear device ID from keychain
    func clearDeviceId() throws {
        try delete(for: Self.deviceIdKey)
    }
}
