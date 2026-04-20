// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// SDK-wide state: initialization, environment, API key, auth tokens,
/// device registration. Wraps ra_state_* / ra_init C ABI.
///
///     try SDKState.initialize(apiKey: "ra-...", environment: .production)
///     SDKState.setAuth(access: "eyJ...", refresh: "eyJ...", expiresAt: ...)
///     if SDKState.isAuthenticated { … }
public enum SDKState {

    public enum Environment: Sendable, CustomStringConvertible {
        case development, staging, production

        var raw: Int32 {
            switch self {
            case .development: return Int32(RA_ENVIRONMENT_DEVELOPMENT)
            case .staging:     return Int32(RA_ENVIRONMENT_STAGING)
            case .production:  return Int32(RA_ENVIRONMENT_PRODUCTION)
            }
        }

        init(raw: Int32) {
            switch raw {
            case Int32(RA_ENVIRONMENT_DEVELOPMENT): self = .development
            case Int32(RA_ENVIRONMENT_STAGING):     self = .staging
            default:                                 self = .production
            }
        }

        public var description: String {
            switch self {
            case .development: return "development"
            case .staging:     return "staging"
            case .production:  return "production"
            }
        }
    }

    public enum LogLevel: Sendable {
        case trace, debug, info, warn, error, fatal

        var raw: Int32 {
            switch self {
            case .trace: return Int32(RA_LOG_LEVEL_TRACE)
            case .debug: return Int32(RA_LOG_LEVEL_DEBUG)
            case .info:  return Int32(RA_LOG_LEVEL_INFO)
            case .warn:  return Int32(RA_LOG_LEVEL_WARN)
            case .error: return Int32(RA_LOG_LEVEL_ERROR)
            case .fatal: return Int32(RA_LOG_LEVEL_FATAL)
            }
        }
    }

    /// Full auth token set. `expiresAt` is the Unix timestamp in seconds.
    /// Pass 0 when the token has no declared expiry.
    public struct Auth: Sendable {
        public var accessToken: String
        public var refreshToken: String
        public var expiresAt: Int64
        public var userId: String?
        public var organizationId: String?
        public var deviceId: String?

        public init(accessToken: String, refreshToken: String = "",
                    expiresAt: Int64 = 0, userId: String? = nil,
                    organizationId: String? = nil, deviceId: String? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.userId = userId
            self.organizationId = organizationId
            self.deviceId = deviceId
        }
    }

    /// Initializes the SDK. Sets environment, API key, base URL, device ID.
    /// Rehydrates previously-stored tokens through the persistence callback
    /// if one has been registered.
    public static func initialize(
        apiKey: String,
        environment: Environment = .production,
        baseUrl: String? = nil,
        deviceId: String? = nil,
        logLevel: LogLevel = .info
    ) throws {
        ra_logger_set_min_level(ra_log_level_t(logLevel.raw))

        let status: Int32 = apiKey.withCString { keyPtr in
            withOptionalCString(baseUrl) { urlPtr in
                withOptionalCString(deviceId) { devPtr in
                    ra_state_initialize(ra_environment_t(environment.raw),
                                         keyPtr, urlPtr, devPtr)
                }
            }
        }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_state_initialize")
        }
    }

    public static var isInitialized: Bool { ra_state_is_initialized() }

    public static var environment: Environment {
        Environment(raw: Int32(ra_state_get_environment()))
    }

    public static var apiKey: String {
        String(cString: ra_state_get_api_key())
    }

    public static var baseUrl: String {
        String(cString: ra_state_get_base_url())
    }

    public static var deviceId: String {
        String(cString: ra_state_get_device_id())
    }

    /// Wipes API key, tokens, device-registered flag. Environment + base URL
    /// persist — call `initialize` again to change those.
    public static func reset() { ra_state_reset() }

    public static func shutdown() { ra_state_shutdown() }

    // MARK: - Auth

    public static func setAuth(_ auth: Auth) throws {
        let status: Int32 = auth.accessToken.withCString { accessPtr in
            auth.refreshToken.withCString { refreshPtr in
                withOptionalCString(auth.userId) { userPtr in
                    withOptionalCString(auth.organizationId) { orgPtr in
                        withOptionalCString(auth.deviceId) { devPtr in
                            var data = ra_auth_data_t()
                            data.access_token = accessPtr
                            data.refresh_token = refreshPtr
                            data.expires_at_unix = auth.expiresAt
                            data.user_id = userPtr
                            data.organization_id = orgPtr
                            data.device_id = devPtr
                            return ra_state_set_auth(&data)
                        }
                    }
                }
            }
        }
        if status != Int32(RA_OK) {
            throw RunAnywhereError.mapStatus(status, message: "ra_state_set_auth")
        }
    }

    public static var accessToken: String {
        String(cString: ra_state_get_access_token())
    }

    public static var refreshToken: String {
        String(cString: ra_state_get_refresh_token())
    }

    public static var userId: String {
        String(cString: ra_state_get_user_id())
    }

    public static var organizationId: String {
        String(cString: ra_state_get_organization_id())
    }

    public static var tokenExpiresAt: Int64 {
        ra_state_get_token_expires_at()
    }

    public static var isAuthenticated: Bool { ra_state_is_authenticated() }

    /// Returns true when the access token either has no declared expiry or
    /// expires within `horizonSeconds`.
    public static func tokenNeedsRefresh(horizonSeconds: Int = 60) -> Bool {
        ra_state_token_needs_refresh(Int32(horizonSeconds))
    }

    public static func clearAuth() { ra_state_clear_auth() }

    // MARK: - Device registration

    public static var isDeviceRegistered: Bool {
        ra_state_is_device_registered()
    }

    public static func setDeviceRegistered(_ registered: Bool) {
        ra_state_set_device_registered(registered)
    }

    // MARK: - Validation helpers

    public static func validateAPIKey(_ key: String) -> Bool {
        key.withCString { ra_validate_api_key($0) }
    }

    public static func validateBaseURL(_ url: String) -> Bool {
        url.withCString { ra_validate_base_url($0) }
    }

    // MARK: - Auth request/response shaping (ra_auth.h)

    /// Build the JSON body for a POST to the cloud authenticate endpoint.
    public static func buildAuthenticateRequest(apiKey: String, deviceId: String) -> String {
        var out: UnsafeMutablePointer<CChar>?
        let rc = apiKey.withCString { ak in
            deviceId.withCString { di in
                ra_auth_build_authenticate_request(ak, di, &out)
            }
        }
        guard rc == RA_OK, let raw = out else { return "{}" }
        defer { ra_auth_string_free(out) }
        return String(cString: raw)
    }

    /// Build the JSON body for a token-refresh POST using the stored refresh token.
    public static func buildRefreshRequest() -> String {
        var out: UnsafeMutablePointer<CChar>?
        let rc = ra_auth_build_refresh_request(&out)
        guard rc == RA_OK, let raw = out else { return "{}" }
        defer { ra_auth_string_free(out) }
        return String(cString: raw)
    }

    /// Parse an authenticate response (JSON string) and persist the returned
    /// tokens into the core `AuthManager` singleton. Returns true on success.
    @discardableResult
    public static func handleAuthenticateResponse(_ json: String) -> Bool {
        json.withCString { ra_auth_handle_authenticate_response($0) == RA_OK }
    }

    /// Parse a token-refresh response and update the stored access token.
    @discardableResult
    public static func handleRefreshResponse(_ json: String) -> Bool {
        json.withCString { ra_auth_handle_refresh_response($0) == RA_OK }
    }

    /// Access token, or nil if not authenticated or token is expired.
    public static var validAccessToken: String? {
        guard let ptr = ra_auth_get_valid_token() else { return nil }
        return String(cString: ptr)
    }
}

// MARK: - C-string interop

/// Runs `body` with the CString of `s`, or nil if `s` is nil. Avoids the
/// nested-escaping-closure issue when withCString can't be called on
/// Optional<String>.
private func withOptionalCString<R>(_ s: String?,
                                     _ body: (UnsafePointer<CChar>?) -> R)
    -> R
{
    guard let s else { return body(nil) }
    return s.withCString { body($0) }
}
