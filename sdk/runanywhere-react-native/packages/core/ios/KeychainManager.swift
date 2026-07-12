/**
 * KeychainManager.swift
 *
 * iOS Keychain manager for secure storage used by the RN core pod's
 * `PlatformAdapterBridge.m` `[KeychainManager shared]` ObjC consumer.
 *
 * This is intentionally a small per-pod facade and NOT a copy of the
 * full Swift SDK class. The Swift SDK's
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift`
 * is owned by the standalone Swift SDK target — it depends on Swift-SDK
 * types (`SDKException`, `SDKInitParams`, `SDKEnvironment`, `SDKLogger`)
 * that are not vended from the `RunAnywhereCore` CocoaPod (which only
 * ships the `RACommons.xcframework` C ABI). Pulling the Swift SDK class
 * in via SwiftPM here would force the RN pod to also import the entire
 * Swift SDK and would conflict with the C++ commons ABI it already
 * binds.
 *
 * Operations (store/retrieve/delete/exists) construct their Keychain
 * queries through the single `baseQuery(for:)` helper below, mirroring
 * the Swift SDK `KeychainManager.baseQuery` pattern so the two
 * implementations stay structurally aligned. The set/get/delete bodies
 * are now query-shape-only — no per-method duplication of the access
 * control or accessibility flags.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Security/KeychainManager.swift
 */

import Foundation
import Security

/// Keychain manager for secure storage used by the RN core pod (singleton).
@objc public class KeychainManager: NSObject {

    // MARK: - Singleton

    @objc public static let shared = KeychainManager()

    // MARK: - Properties

    private let serviceName = "com.runanywhere.sdk"

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Private Query Builder

    /// Single source of truth for Keychain query construction; mirrors the
    /// Swift SDK `KeychainManager.baseQuery(for:)` so per-op bodies don't
    /// duplicate the service-name / accessibility / class flags.
    private func baseQuery(forKey key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    // MARK: - Public API (ObjC-exposed for PlatformAdapterBridge.m)

    /// Store a value in the keychain.
    @objc public func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Update-then-add pattern matches the Swift SDK store(data:for:).
        var query = baseQuery(forKey: key)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    /// Retrieve a required value while preserving the Keychain status for the
    /// C bridge. `errSecItemNotFound` is the clean-miss signal; every other
    /// status is a real secure-storage failure.
    @objc(getRequiredValueForKey:error:)
    public func getRequiredValue(forKey key: String) throws -> String {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
        }
        return value
    }

    /// Delete a value from the keychain.
    @objc public func delete(forKey key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

}
