import Foundation
import Security

/// Keychain manager for secure storage of sensitive data
public final class KeychainManager {

    // MARK: - Singleton

    public static let shared = KeychainManager()

    // MARK: - Properties

    private let serviceName = "com.runanywhere.sdk"
    private let accessGroup: String? = nil // Set if you need app group sharing
    private let logger = SDKLogger(category: "KeychainManager")

    // MARK: - Keychain Keys

    private enum KeychainKey: String {
        // SDK Core
        case apiKey = "com.runanywhere.sdk.apiKey"
        case baseURL = "com.runanywhere.sdk.baseURL"
        case environment = "com.runanywhere.sdk.environment"

        // Device Identity
        case deviceUUID = "com.runanywhere.sdk.device.uuid"
        case deviceFingerprint = "com.runanywhere.sdk.device.fingerprint"
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods - SDK Credentials

    /// Store SDK initialization parameters securely
    /// - Parameter params: SDK initialization parameters
    /// - Throws: KeychainError if storage fails
    public func storeSDKParams(_ params: SDKInitParams) throws {
        // Store API key
        try store(params.apiKey, for: KeychainKey.apiKey.rawValue)

        // Store base URL
        try store(params.baseURL.absoluteString, for: KeychainKey.baseURL.rawValue)

        // Store environment
        try store(params.environment.rawValue, for: KeychainKey.environment.rawValue)

        logger.info("SDK parameters stored securely in keychain")
    }

    /// Retrieve stored SDK parameters
    /// - Returns: Stored SDK parameters if available
    public func retrieveSDKParams() -> SDKInitParams? {
        guard let apiKey = try? retrieve(for: KeychainKey.apiKey.rawValue),
              let urlString = try? retrieve(for: KeychainKey.baseURL.rawValue),
              let url = URL(string: urlString),
              let envString = try? retrieve(for: KeychainKey.environment.rawValue),
              let environment = SDKEnvironment(rawValue: envString) else {
            logger.debug("No stored SDK parameters found in keychain")
            return nil
        }

        logger.debug("Retrieved SDK parameters from keychain")
        return SDKInitParams(apiKey: apiKey, baseURL: url, environment: environment)
    }

    /// Clear stored SDK parameters
    public func clearSDKParams() throws {
        try delete(for: KeychainKey.apiKey.rawValue)
        try delete(for: KeychainKey.baseURL.rawValue)
        try delete(for: KeychainKey.environment.rawValue)
        logger.info("SDK parameters cleared from keychain")
    }

    // MARK: - Device Identity Methods

    /// Store device UUID
    /// - Parameter uuid: Device UUID to store
    public func storeDeviceUUID(_ uuid: String) throws {
        try store(uuid, for: KeychainKey.deviceUUID.rawValue)
        logger.debug("Device UUID stored in keychain")
    }

    /// Retrieve device UUID
    /// - Returns: Stored device UUID if available
    public func retrieveDeviceUUID() -> String? {
        return try? retrieve(for: KeychainKey.deviceUUID.rawValue)
    }

    /// Store device fingerprint
    /// - Parameter fingerprint: Device fingerprint to store
    public func storeDeviceFingerprint(_ fingerprint: String) throws {
        try store(fingerprint, for: KeychainKey.deviceFingerprint.rawValue)
        logger.debug("Device fingerprint stored in keychain")
    }

    /// Retrieve device fingerprint
    /// - Returns: Stored device fingerprint if available
    public func retrieveDeviceFingerprint() -> String? {
        return try? retrieve(for: KeychainKey.deviceFingerprint.rawValue)
    }

    // MARK: - Generic Storage Methods

    /// Store a string value in the keychain
    /// - Parameters:
    ///   - value: String value to store
    ///   - key: Unique key for the value
    /// - Throws: KeychainError if storage fails
    public func store(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        try store(data, for: key)
    }

    /// Store data in the keychain
    /// - Parameters:
    ///   - data: Data to store
    ///   - key: Unique key for the data
    /// - Throws: KeychainError if storage fails
    public func store(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        // Try to update first
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        // If not found, add new item
        if status == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.storageError(status)
        }
    }

    /// Retrieve a string value from the keychain
    /// - Parameter key: Key for the value
    /// - Returns: Stored string value
    /// - Throws: KeychainError if retrieval fails
    public func retrieve(for key: String) throws -> String {
        let data = try retrieveData(for: key)

        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingError
        }

        return string
    }

    /// Retrieve data from the keychain
    /// - Parameter key: Key for the data
    /// - Returns: Stored data
    /// - Throws: KeychainError if retrieval fails
    public func retrieveData(for key: String) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.retrievalError(status)
        }

        return data
    }

    /// Delete an item from the keychain
    /// - Parameter key: Key for the item to delete
    /// - Throws: KeychainError if deletion fails
    public func delete(for key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionError(status)
        }
    }

    /// Check if an item exists in the keychain
    /// - Parameter key: Key to check
    /// - Returns: True if item exists
    public func exists(for key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Private Methods

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false // Don't sync to iCloud Keychain
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Set accessibility - available when unlocked
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return query
    }
}

// MARK: - KeychainError

/// Errors that can occur during keychain operations
public enum KeychainError: LocalizedError {
    case encodingError
    case decodingError
    case itemNotFound
    case storageError(OSStatus)
    case retrievalError(OSStatus)
    case deletionError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode data for keychain storage"
        case .decodingError:
            return "Failed to decode data from keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        case .storageError(let status):
            return "Failed to store item in keychain: \(status)"
        case .retrievalError(let status):
            return "Failed to retrieve item from keychain: \(status)"
        case .deletionError(let status):
            return "Failed to delete item from keychain: \(status)"
        }
    }
}
