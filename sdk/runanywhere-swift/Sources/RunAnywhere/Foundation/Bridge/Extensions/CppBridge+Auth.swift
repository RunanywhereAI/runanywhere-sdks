//
//  CppBridge+Auth.swift
//  RunAnywhere SDK
//
//  Authentication bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Auth Bridge (Complete Auth Flow)

extension CppBridge {

    /// Complete authentication bridge
    /// Handles full auth flow: JSON building, HTTP, parsing, state storage
    public enum Auth {

        private static let logger = SDKLogger(category: "CppBridge.Auth")

        // MARK: - Complete Auth Flow

        /// Authenticate with backend
        /// - Parameter apiKey: API key for authentication
        /// - Returns: Authentication response
        /// - Throws: SDKError on failure
        @discardableResult
        public static func authenticate(apiKey: String) async throws -> AuthenticationResponse {
            let deviceId = DeviceIdentity.persistentUUID

            // 1. Build request JSON via C++
            guard let json = buildAuthenticateRequestJSON(
                apiKey: apiKey,
                deviceId: deviceId,
                platform: SDKConstants.platform,
                sdkVersion: SDKConstants.version
            ) else {
                throw SDKError.general(.validationFailed, "Failed to build auth request")
            }

            logger.info("Starting authentication...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_AUTHENTICATE,
                json: json,
                requiresAuth: false
            )

            // 3. Parse response via Codable
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuthenticationResponse.self, from: responseData)

            // 4. Store in C++ state
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            State.setAuth(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: expiresAt,
                userId: response.userId,
                organizationId: response.organizationId,
                deviceId: response.deviceId
            )

            // 5. Store in Keychain
            try storeTokensInKeychain(response)

            logger.info("Authentication successful")
            return response
        }

        /// Refresh access token
        /// - Returns: New access token
        /// - Throws: SDKError on failure
        @discardableResult
        public static func refreshToken() async throws -> String {
            guard let refreshToken = State.refreshToken else {
                throw SDKError.authentication(.invalidAPIKey, "No refresh token")
            }

            guard let deviceId = State.deviceId else {
                throw SDKError.authentication(.authenticationFailed, "No device ID")
            }

            // 1. Build refresh request JSON via C++
            guard let json = buildRefreshRequestJSON(deviceId: deviceId, refreshToken: refreshToken) else {
                throw SDKError.general(.validationFailed, "Failed to build refresh request")
            }

            logger.debug("Refreshing access token...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_REFRESH,
                json: json,
                requiresAuth: false
            )

            // 3. Parse response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuthenticationResponse.self, from: responseData)

            // 4. Store in C++ state
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            State.setAuth(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: expiresAt,
                userId: response.userId,
                organizationId: response.organizationId,
                deviceId: response.deviceId
            )

            // 5. Store in Keychain
            try storeTokensInKeychain(response)

            logger.info("Token refresh successful")
            return response.accessToken
        }

        /// Get valid access token (refresh if needed)
        /// - Returns: Valid access token
        /// - Throws: SDKError if no valid token available
        public static func getAccessToken() async throws -> String {
            // Check if current token is valid
            if let token = State.accessToken, !State.tokenNeedsRefresh {
                return token
            }

            // Try to refresh
            if State.refreshToken != nil {
                return try await refreshToken()
            }

            throw SDKError.authentication(.authenticationFailed, "No valid token")
        }

        /// Clear authentication state
        public static func clearAuth() throws {
            // Clear C++ state
            State.clearAuth()

            // Clear Keychain
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.deviceId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.userId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.organizationId")

            logger.info("Authentication cleared")
        }

        /// Check if currently authenticated
        public static var isAuthenticated: Bool {
            State.isAuthenticated
        }

        // MARK: - Keychain Storage

        private static func storeTokensInKeychain(_ response: AuthenticationResponse) throws {
            try KeychainManager.shared.store(response.accessToken, for: "com.runanywhere.sdk.accessToken")
            try KeychainManager.shared.store(response.refreshToken, for: "com.runanywhere.sdk.refreshToken")
            try KeychainManager.shared.store(response.deviceId, for: "com.runanywhere.sdk.deviceId")
            if let userId = response.userId {
                try KeychainManager.shared.store(userId, for: "com.runanywhere.sdk.userId")
            }
            try KeychainManager.shared.store(response.organizationId, for: "com.runanywhere.sdk.organizationId")
        }

        // MARK: - JSON Building (existing methods)

        /// Build authentication request JSON via C++
        /// - Parameters:
        ///   - apiKey: API key
        ///   - deviceId: Device ID
        ///   - platform: Platform string (e.g., "ios")
        ///   - sdkVersion: SDK version string
        /// - Returns: JSON string for POST body, or nil on error
        public static func buildAuthenticateRequestJSON(
            apiKey: String,
            deviceId: String,
            platform: String,
            sdkVersion: String
        ) -> String? {
            return apiKey.withCString { key in
                deviceId.withCString { did in
                    platform.withCString { plat in
                        sdkVersion.withCString { ver in
                            var request = rac_auth_request_t(
                                api_key: key,
                                device_id: did,
                                platform: plat,
                                sdk_version: ver
                            )

                            guard let jsonPtr = rac_auth_request_to_json(&request) else {
                                return nil
                            }

                            let json = String(cString: jsonPtr)
                            free(jsonPtr)
                            return json
                        }
                    }
                }
            }
        }

        /// Build refresh token request JSON via C++
        /// - Parameters:
        ///   - deviceId: Device ID
        ///   - refreshToken: Refresh token
        /// - Returns: JSON string for POST body, or nil on error
        public static func buildRefreshRequestJSON(
            deviceId: String,
            refreshToken: String
        ) -> String? {
            return deviceId.withCString { did in
                refreshToken.withCString { token in
                    var request = rac_refresh_request_t(
                        device_id: did,
                        refresh_token: token
                    )

                    guard let jsonPtr = rac_refresh_request_to_json(&request) else {
                        return nil
                    }

                    let json = String(cString: jsonPtr)
                    free(jsonPtr)
                    return json
                }
            }
        }

        /// Parse API error from HTTP response via C++
        /// - Parameters:
        ///   - statusCode: HTTP status code
        ///   - body: Response body data
        ///   - url: Request URL
        /// - Returns: SDKError with appropriate category and message
        public static func parseAPIError(
            statusCode: Int32,
            body: Data?,
            url: String?
        ) -> SDKError {
            let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let urlString = url ?? ""

            var error = rac_api_error_t()

            let result = bodyString.withCString { bodyPtr in
                urlString.withCString { urlPtr in
                    rac_api_error_from_response(statusCode, bodyPtr, urlPtr, &error)
                }
            }

            defer {
                rac_api_error_free(&error)
            }

            // Use C++ parsed message, or fallback
            let message: String
            if result == 0, let msgPtr = error.message {
                message = String(cString: msgPtr)
            } else {
                message = "HTTP \(statusCode)"
            }

            // Map status code to SDKError category
            switch statusCode {
            case 401:
                return SDKError.network(.unauthorized, message)
            case 403:
                return SDKError.network(.forbidden, message)
            case 404:
                return SDKError.network(.invalidResponse, message)
            case 408, 504:
                return SDKError.network(.timeout, message)
            case 422:
                return SDKError.network(.validationFailed, message)
            case 400..<500:
                return SDKError.network(.httpError, "Client error \(statusCode): \(message)")
            case 500..<600:
                return SDKError.network(.serverError, "Server error \(statusCode): \(message)")
            default:
                return SDKError.network(.unknown, "\(message) (status: \(statusCode))")
            }
        }
    }
}
