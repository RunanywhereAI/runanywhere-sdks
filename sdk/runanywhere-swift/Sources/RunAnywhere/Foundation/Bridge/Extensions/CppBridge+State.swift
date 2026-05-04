//
//  CppBridge+State.swift
//  RunAnywhere SDK
//
//  SDK state management bridge extension for C++ interop.
//
//  Non-auth state (environment, API key, base URL, device ID, device
//  registration flag) lives in rac_sdk_state. Auth state (tokens,
//  user/org IDs, expiry, refresh-window math, persistence) lives in
//  rac_auth_manager — this file exposes auth accessors by delegating
//  to rac_auth_* directly so there's a single source of truth.
//

import CRACommons
import Foundation

// MARK: - State Bridge (Centralized SDK State)

extension CppBridge {

    /// SDK State bridge - centralized state management in C++
    /// C++ owns runtime state; Swift handles persistence via the
    /// rac_secure_storage_t vtable installed here.
    public enum State {

        private static var authStorageInstalled = false

        // MARK: - Initialization

        /// Initialize C++ state manager
        /// - Parameters:
        ///   - environment: SDK environment
        ///   - apiKey: API key
        ///   - baseURL: Base URL
        ///   - deviceId: Persistent device ID
        public static func initialize(
            environment: SDKEnvironment,
            apiKey: String,
            baseURL: URL,
            deviceId: String
        ) {
            apiKey.withCString { key in
                baseURL.absoluteString.withCString { url in
                    deviceId.withCString { did in
                        _ = rac_state_initialize(
                            Environment.toC(environment),
                            key,
                            url,
                            did
                        )
                    }
                }
            }

            // Initialize SDK config with version (required for device registration)
            // This populates rac_sdk_get_config() which device registration uses
            let sdkVersion = SDKConstants.version
            let platform = SDKConstants.platform

            // Use withCString to ensure strings remain valid during the call
            sdkVersion.withCString { sdkVer in
                platform.withCString { plat in
                    apiKey.withCString { key in
                        baseURL.absoluteString.withCString { url in
                            deviceId.withCString { did in
                                var sdkConfig = rac_sdk_config_t()
                                sdkConfig.environment = Environment.toC(environment)
                                sdkConfig.api_key = apiKey.isEmpty ? nil : key
                                sdkConfig.base_url = baseURL.absoluteString.isEmpty ? nil : url
                                sdkConfig.device_id = deviceId.isEmpty ? nil : did
                                sdkConfig.platform = plat
                                sdkConfig.sdk_version = sdkVer
                                _ = rac_sdk_init(&sdkConfig)
                            }
                        }
                    }
                }
            }

            // Install Keychain-backed secure storage into the auth manager and
            // restore any previously persisted tokens.
            installAuthSecureStorage()

            SDKLogger(category: "CppBridge.State").debug("C++ state initialized")
        }

        /// Check if state is initialized
        public static var isInitialized: Bool {
            rac_state_is_initialized()
        }

        /// Reset state (for testing)
        public static func reset() {
            rac_state_reset()
            rac_auth_reset()
        }

        /// Shutdown state manager
        public static func shutdown() {
            rac_state_shutdown()
            rac_auth_reset()
            authStorageInstalled = false
        }

        // MARK: - Environment Queries

        /// Get current environment from C++ state
        public static var environment: SDKEnvironment {
            Environment.fromC(rac_state_get_environment())
        }

        /// Get base URL from C++ state
        public static var baseURL: String? {
            guard let ptr = rac_state_get_base_url() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        /// Get API key from C++ state
        public static var apiKey: String? {
            guard let ptr = rac_state_get_api_key() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        /// Get device ID from C++ state
        public static var deviceId: String? {
            guard let ptr = rac_state_get_device_id() else { return nil }
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }

        // MARK: - Auth State (delegated to rac_auth_manager)

        /// Get access token from the auth manager
        public static var accessToken: String? {
            guard let ptr = rac_auth_get_access_token() else { return nil }
            return String(cString: ptr)
        }

        /// Check if authenticated (valid non-expired token)
        public static var isAuthenticated: Bool {
            rac_auth_is_authenticated()
        }

        /// Check if token needs refresh
        public static var tokenNeedsRefresh: Bool {
            rac_auth_needs_refresh()
        }

        /// Get user ID from the auth manager
        public static var userId: String? {
            guard let ptr = rac_auth_get_user_id() else { return nil }
            return String(cString: ptr)
        }

        /// Get organization ID from the auth manager
        public static var organizationId: String? {
            guard let ptr = rac_auth_get_organization_id() else { return nil }
            return String(cString: ptr)
        }

        /// Clear authentication state (in-memory + persisted)
        public static func clearAuth() {
            rac_auth_clear()
            SDKLogger(category: "CppBridge.State").debug("Auth state cleared")
        }

        // MARK: - Device State

        /// Set device registration status
        public static func setDeviceRegistered(_ registered: Bool) {
            rac_state_set_device_registered(registered)
        }

        /// Check if device is registered
        public static var isDeviceRegistered: Bool {
            rac_state_is_device_registered()
        }

        // MARK: - Persistence (Keychain Integration)

        /// Install Keychain-backed secure storage into the rac_auth_manager.
        ///
        /// Registers the vtable, then calls rac_auth_load_stored_tokens to
        /// restore any tokens persisted from a previous launch. Without this
        /// wiring, rac_auth_save_tokens / rac_auth_clear are no-ops and
        /// tokens are lost on every process restart.
        private static func installAuthSecureStorage() {
            guard !authStorageInstalled else { return }

            var storage = rac_secure_storage_t(
                store: authSecureStorageStore,
                retrieve: authSecureStorageRetrieve,
                delete_key: authSecureStorageDelete,
                context: nil
            )

            rac_auth_init(&storage)

            // Restore any previously persisted tokens.
            _ = rac_auth_load_stored_tokens()

            authStorageInstalled = true
            SDKLogger(category: "CppBridge.State").debug("Keychain secure storage installed into rac_auth_manager")
        }
    }
}

// MARK: - C-callable secure storage shims for rac_auth_manager
//
// These top-level `@convention(c)` functions are the vtable slots passed to
// rac_auth_init. They must be non-capturing (no self / state) so Swift can
// emit them as plain C function pointers. All state lives in the global
// KeychainManager.shared.

private func authSecureStorageStore(
    key: UnsafePointer<CChar>?,
    value: UnsafePointer<CChar>?,
    context _: UnsafeMutableRawPointer?
) -> Int32 {
    guard let key = key, let value = value else { return -1 }
    let keyStr = String(cString: key)
    let valueStr = String(cString: value)
    do {
        try KeychainManager.shared.store(valueStr, for: keyStr)
        return 0
    } catch {
        return -1
    }
}

private func authSecureStorageRetrieve(
    key: UnsafePointer<CChar>?,
    outValue: UnsafeMutablePointer<CChar>?,
    bufferSize: Int,
    context _: UnsafeMutableRawPointer?
) -> Int32 {
    guard let key = key, let outValue = outValue, bufferSize > 0 else { return -1 }
    let keyStr = String(cString: key)
    do {
        guard let value = try KeychainManager.shared.retrieveIfExists(for: keyStr),
              !value.isEmpty else {
            return -1
        }
        // Copy UTF-8 bytes + trailing NUL into the caller-provided buffer.
        let utf8 = value.utf8CString  // includes trailing NUL
        if utf8.count > bufferSize { return -1 }
        utf8.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                outValue.update(from: base, count: utf8.count)
            }
        }
        // Per header contract: return length excluding NUL terminator.
        return Int32(utf8.count - 1)
    } catch {
        return -1
    }
}

private func authSecureStorageDelete(
    key: UnsafePointer<CChar>?,
    context _: UnsafeMutableRawPointer?
) -> Int32 {
    guard let key = key else { return -1 }
    let keyStr = String(cString: key)
    do {
        try KeychainManager.shared.delete(for: keyStr)
        return 0
    } catch {
        return -1
    }
}
