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

    /// A local Mac build is signed ad-hoc, and that signature changes on every
    /// rebuild, so the Keychain treats each build as a different program and
    /// prompts for the login password once per stored item per launch. Debug Mac
    /// builds read and write a file in Application Support instead. Release and
    /// every iOS build keep using the Keychain.
    private var usesFileStore: Bool {
        #if os(macOS) && DEBUG
        return true
        #else
        return false
        #endif
    }

    private func fileURL(for key: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("RunAnywhereAI", isDirectory: true)
        .appendingPathComponent("DebugSecrets", isDirectory: true)

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Key names come from the app, not from user input, but percent-encoding
        // keeps a future key with a slash from escaping the directory.
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return base.appendingPathComponent(name)
    }

    func save(key: String, data: Data) throws {
        if usesFileStore {
            do {
                try data.write(to: try fileURL(for: key), options: [.atomic])
                return
            } catch {
                throw KeychainError.saveFailed
            }
        }

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
        if usesFileStore {
            guard let url = try? fileURL(for: key) else { return nil }
            return try? Data(contentsOf: url)
        }

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
        if usesFileStore {
            guard let url = try? fileURL(for: key) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

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
