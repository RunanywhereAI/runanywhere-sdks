// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Apple Keychain wrapper. Replaces the inline Keychain calls in
// PlatformAdapter.swift with a proper abstraction that supports access
// control and optional biometric gating. Ports the capability surface
// from legacy `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/
// Security/KeychainManager.swift`.

#if canImport(Security)
import Security
#endif
import Foundation

@MainActor
public enum KeychainManager {

    public enum Accessibility: Sendable {
        case whenUnlocked
        case afterFirstUnlock
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly
        case whenPasscodeSetThisDeviceOnly

        var attr: CFString {
            #if canImport(Security)
            switch self {
            case .whenUnlocked:                       return kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlock:                   return kSecAttrAccessibleAfterFirstUnlock
            case .whenUnlockedThisDeviceOnly:         return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly:     return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenPasscodeSetThisDeviceOnly:      return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            }
            #else
            return "" as CFString
            #endif
        }
    }

    public enum Error: Swift.Error {
        case unavailable
        case itemNotFound
        case authFailed
        case osStatus(Int32)
    }

    #if canImport(Security)

    /// Store a string value for a key. `accessibility` controls when the
    /// item is readable. `requireBiometric` additionally requires Face ID /
    /// Touch ID / device passcode on read.
    public static func set(_ value: String, forKey key: String,
                            accessibility: Accessibility = .afterFirstUnlock,
                            requireBiometric: Bool = false,
                            service: String = "runanywhere") throws {
        try delete(key: key, service: service)
        guard let data = value.data(using: .utf8) else { throw Error.unavailable }
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        if requireBiometric {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, accessibility.attr, .userPresence, &error
            ) else { throw Error.osStatus(-1) }
            attributes[kSecAttrAccessControl as String] = access
        } else {
            attributes[kSecAttrAccessible as String] = accessibility.attr
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.osStatus(status) }
    }

    /// Read a string value. Returns `nil` when the item does not exist.
    public static func get(key: String, service: String = "runanywhere") throws -> String? {
        let query: [String: Any] = [
            kSecClass as String:             kSecClassGenericPassword,
            kSecAttrService as String:       service,
            kSecAttrAccount as String:       key,
            kSecReturnData as String:        true,
            kSecMatchLimit as String:        kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw Error.authFailed
        }
        guard status == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else {
            throw Error.osStatus(status)
        }
        return s
    }

    @discardableResult
    public static func delete(key: String, service: String = "runanywhere") throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Error.osStatus(status) }
        return true
    }

    #else

    public static func set(_ value: String, forKey key: String,
                            accessibility: Accessibility = .afterFirstUnlock,
                            requireBiometric: Bool = false,
                            service: String = "runanywhere") throws {
        throw Error.unavailable
    }
    public static func get(key: String, service: String = "runanywhere") throws -> String? { nil }
    public static func delete(key: String, service: String = "runanywhere") throws -> Bool { false }

    #endif
}
