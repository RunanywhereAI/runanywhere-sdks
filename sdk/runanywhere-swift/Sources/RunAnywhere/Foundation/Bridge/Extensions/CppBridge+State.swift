//
//  CppBridge+State.swift
//  RunAnywhere SDK
//
//  SDK state management bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - State Bridge (Centralized SDK State)

extension CppBridge {

    /// SDK State bridge - centralized state management in C++
    /// C++ owns runtime state; Swift handles persistence (Keychain)
    public enum State {

        private static var persistenceRegistered = false

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

            // Register Keychain persistence callbacks
            registerPersistenceCallbacks()

            // Load any stored tokens from Keychain into C++ state
            loadStoredAuth()

            SDKLogger(category: "CppBridge.State").debug("C++ state initialized")
        }

        /// Check if state is initialized
        public static var isInitialized: Bool {
            rac_state_is_initialized()
        }

        /// Reset state (for testing)
        public static func reset() {
            rac_state_reset()
        }

        /// Shutdown state manager
        public static func shutdown() {
            rac_state_shutdown()
            persistenceRegistered = false
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

        // MARK: - Auth State

        /// Set authentication state after successful HTTP auth
        /// - Parameters:
        ///   - accessToken: Access token
        ///   - refreshToken: Refresh token
        ///   - expiresAt: Token expiry date
        ///   - userId: User ID (nullable)
        ///   - organizationId: Organization ID
        ///   - deviceId: Device ID from response
        public static func setAuth(
            accessToken: String,
            refreshToken: String,
            expiresAt: Date,
            userId: String?,
            organizationId: String,
            deviceId: String
        ) {
            let expiresAtUnix = Int64(expiresAt.timeIntervalSince1970)

            accessToken.withCString { access in
                refreshToken.withCString { refresh in
                    organizationId.withCString { org in
                        deviceId.withCString { did in
                            var authData = rac_auth_data_t(
                                access_token: access,
                                refresh_token: refresh,
                                expires_at_unix: expiresAtUnix,
                                user_id: nil,
                                organization_id: org,
                                device_id: did
                            )

                            if let userId = userId {
                                userId.withCString { user in
                                    authData.user_id = user
                                    _ = rac_state_set_auth(&authData)
                                }
                            } else {
                                _ = rac_state_set_auth(&authData)
                            }
                        }
                    }
                }
            }

            SDKLogger(category: "CppBridge.State").debug("Auth state set in C++")
        }

        /// Get access token from C++ state
        public static var accessToken: String? {
            guard let ptr = rac_state_get_access_token() else { return nil }
            return String(cString: ptr)
        }

        /// Get refresh token from C++ state
        public static var refreshToken: String? {
            guard let ptr = rac_state_get_refresh_token() else { return nil }
            return String(cString: ptr)
        }

        /// Check if authenticated (valid non-expired token)
        public static var isAuthenticated: Bool {
            rac_state_is_authenticated()
        }

        /// Check if token needs refresh
        public static var tokenNeedsRefresh: Bool {
            rac_state_token_needs_refresh()
        }

        /// Get token expiry timestamp
        public static var tokenExpiresAt: Date? {
            let unix = rac_state_get_token_expires_at()
            return unix > 0 ? Date(timeIntervalSince1970: TimeInterval(unix)) : nil
        }

        /// Get user ID from C++ state
        public static var userId: String? {
            guard let ptr = rac_state_get_user_id() else { return nil }
            return String(cString: ptr)
        }

        /// Get organization ID from C++ state
        public static var organizationId: String? {
            guard let ptr = rac_state_get_organization_id() else { return nil }
            return String(cString: ptr)
        }

        /// Clear authentication state
        public static func clearAuth() {
            rac_state_clear_auth()
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

        /// Register Keychain persistence callbacks with C++
        private static func registerPersistenceCallbacks() {
            guard !persistenceRegistered else { return }

            rac_state_set_persistence_callbacks(
                keychainPersistCallback,
                keychainLoadCallback,
                nil
            )

            persistenceRegistered = true
        }

        /// Load stored auth from Keychain into C++ state
        private static func loadStoredAuth() {
            // Load tokens from Keychain (use retrieveIfExists to avoid logging errors for missing items)
            // retrieveIfExists returns String? and can throw
            let accessToken: String?
            let refreshToken: String?

            do {
                accessToken = try KeychainManager.shared.retrieveIfExists(for: "com.runanywhere.sdk.accessToken")
                refreshToken = try KeychainManager.shared.retrieveIfExists(for: "com.runanywhere.sdk.refreshToken")
            } catch {
                // Keychain error (not just missing item) - log but don't fail
                SDKLogger(category: "CppBridge.State").debug("Keychain error loading auth: \(error.localizedDescription)")
                return
            }

            guard let accessToken = accessToken,
                  let refreshToken = refreshToken else {
                // No stored auth tokens found - this is normal on first launch
                SDKLogger(category: "CppBridge.State").debug("No stored auth data found in Keychain (expected on first launch)")
                return
            }

            // Load additional fields (optional - these may not exist)
            let userId = try? KeychainManager.shared.retrieveIfExists(for: "com.runanywhere.sdk.userId")
            let orgId = try? KeychainManager.shared.retrieveIfExists(for: "com.runanywhere.sdk.organizationId")
            let deviceIdStored = try? KeychainManager.shared.retrieveIfExists(for: "com.runanywhere.sdk.deviceId")

            // Set in C++ state (use a far-future expiry for loaded tokens - they'll be refreshed if needed)
            accessToken.withCString { access in
                refreshToken.withCString { refresh in
                    (orgId ?? "").withCString { org in
                        (deviceIdStored ?? DeviceIdentity.persistentUUID).withCString { did in
                            var authData = rac_auth_data_t(
                                access_token: access,
                                refresh_token: refresh,
                                expires_at_unix: 0, // Unknown - will check via API
                                user_id: nil,
                                organization_id: org,
                                device_id: did
                            )

                            if let userId = userId {
                                userId.withCString { user in
                                    authData.user_id = user
                                    _ = rac_state_set_auth(&authData)
                                }
                            } else {
                                _ = rac_state_set_auth(&authData)
                            }
                        }
                    }
                }
            }

            SDKLogger(category: "CppBridge.State").debug("Loaded stored auth from Keychain")
        }
    }
}

// MARK: - Keychain Persistence Callbacks

/// C callback for persisting state to Keychain
private func keychainPersistCallback(
    key: UnsafePointer<CChar>?,
    value: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) {
    guard let key = key else { return }
    let keyString = String(cString: key)

    // Map C++ keys to Keychain keys
    let keychainKey: String
    switch keyString {
    case "access_token":
        keychainKey = "com.runanywhere.sdk.accessToken"
    case "refresh_token":
        keychainKey = "com.runanywhere.sdk.refreshToken"
    default:
        return // Ignore unknown keys
    }

    if let value = value {
        // Store value
        let valueString = String(cString: value)
        try? KeychainManager.shared.store(valueString, for: keychainKey)
    } else {
        // Delete value
        try? KeychainManager.shared.delete(for: keychainKey)
    }
}

/// C callback for loading state from Keychain
private func keychainLoadCallback(
    key: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> UnsafePointer<CChar>? {
    guard let key = key else { return nil }
    let keyString = String(cString: key)

    // Map C++ keys to Keychain keys
    let keychainKey: String
    switch keyString {
    case "access_token":
        keychainKey = "com.runanywhere.sdk.accessToken"
    case "refresh_token":
        keychainKey = "com.runanywhere.sdk.refreshToken"
    default:
        return nil
    }

    // Load from Keychain
    // Note: This returns a pointer that C++ should NOT free
    // The Swift string's memory is managed by Swift
    guard (try? KeychainManager.shared.retrieve(for: keychainKey)) != nil else {
        return nil
    }

    // This is a workaround - we return a static buffer
    // In practice, C++ should call this during init only
    return nil // For now, we load manually via loadStoredAuth()
}
