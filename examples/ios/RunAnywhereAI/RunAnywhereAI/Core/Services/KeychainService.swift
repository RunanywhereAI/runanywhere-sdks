//
//  KeychainService.swift
//  RunAnywhereAI
//
//  Secure storage for API credentials
//

import Foundation

// MARK: - Keychain Service

class KeychainService {
    static let shared = KeychainService()

    private init() {}

    func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }

    func retrieve(key: String) throws -> Data? {
        read(key: key)
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }

    // MARK: - Boolean Helpers

    /// Save a boolean value to keychain
    func saveBool(key: String, value: Bool) throws {
        let data = Data([value ? 1 : 0])
        try save(key: key, data: data)
    }

    /// Load a boolean value from keychain
    func loadBool(key: String, defaultValue: Bool = false) -> Bool {
        guard let data = read(key: key) else {
            return defaultValue
        }
        return data.first == 1
    }
}

enum KeychainError: Error {
    case saveFailed
    case deleteFailed
}
