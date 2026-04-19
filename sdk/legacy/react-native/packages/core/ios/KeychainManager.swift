/**
 * KeychainManager.swift
 *
 * iOS Keychain manager for secure storage of sensitive data.
 * Matches Swift SDK's KeychainManager pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

import Foundation
import Security

/// Keychain manager for secure storage (singleton)
@objc public class KeychainManager: NSObject {
    
    // MARK: - Singleton
    
    @objc public static let shared = KeychainManager()
    
    // MARK: - Properties
    
    private let serviceName = "com.runanywhere.sdk"
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Store a value in the keychain
    /// - Parameters:
    ///   - value: Value to store
    ///   - key: Key to store under
    /// - Returns: true if successful
    @objc public func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        
        // Delete existing item first (update by delete + add)
        _ = delete(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieve a value from the keychain
    /// - Parameter key: Key to retrieve
    /// - Returns: Stored value or nil
    @objc public func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// Delete a value from the keychain
    /// - Parameter key: Key to delete
    /// - Returns: true if successful or item didn't exist
    @objc public func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Check if a key exists in the keychain
    /// - Parameter key: Key to check
    /// - Returns: true if key exists
    @objc public func exists(forKey key: String) -> Bool {
        return get(forKey: key) != nil
    }
    
    // MARK: - Device UUID Convenience
    
    private let deviceUUIDKey = "com.runanywhere.sdk.device.uuid"
    
    /// Store device UUID
    @objc public func storeDeviceUUID(_ uuid: String) -> Bool {
        return set(uuid, forKey: deviceUUIDKey)
    }
    
    /// Retrieve device UUID
    @objc public func retrieveDeviceUUID() -> String? {
        return get(forKey: deviceUUIDKey)
    }
}

