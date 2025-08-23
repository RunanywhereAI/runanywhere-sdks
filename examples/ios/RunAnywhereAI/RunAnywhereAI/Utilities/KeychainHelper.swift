//
//  KeychainHelper.swift
//  RunAnywhereAI
//
//  Helper utility for storing settings securely in the Keychain
//

import Foundation
import Security

class KeychainHelper {

    private static let service = "com.runanywhere.RunAnywhereAI"

    /// Save a boolean value to keychain
    static func save(key: String, data: Bool) {
        let data = Data([data ? 1 : 0])
        save(key: key, data: data)
    }

    /// Save data to keychain
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing item if it exists
        SecItemDelete(query as CFDictionary)

        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Load a boolean value from keychain
    static func loadBool(key: String, defaultValue: Bool = false) -> Bool {
        guard let data = load(key: key) else {
            return defaultValue
        }
        return data.first == 1
    }

    /// Load data from keychain
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        } else {
            return nil
        }
    }

    /// Delete an item from keychain
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
