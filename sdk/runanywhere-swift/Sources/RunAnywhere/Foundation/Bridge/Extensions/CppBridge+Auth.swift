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

        /// Authenticate with backend.
        /// C++ parses the response JSON, updates internal auth state, and
        /// (when secure-storage callbacks are registered) persists tokens.
        /// - Parameter apiKey: API key for authentication
        /// - Throws: SDKException on failure
        public static func authenticate(apiKey: String) async throws {
            let deviceId = DeviceIdentity.persistentUUID

            // 1. Build request JSON via C++
            guard let json = buildAuthenticateRequestJSON(
                apiKey: apiKey,
                deviceId: deviceId,
                platform: SDKConstants.platform,
                sdkVersion: SDKConstants.version
            ) else {
                throw SDKException.general(.validationFailed, "Failed to build auth request")
            }

            logger.info("Starting authentication...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_AUTHENTICATE,
                json: json,
                requiresAuth: false
            )

            // 3. Hand raw JSON to C++: parse, update in-memory auth state,
            //    and (with secure-storage wired) persist — one atomic call.
            try handleAuthResponse(
                responseData,
                handler: rac_auth_handle_authenticate_response,
                successMessage: "Authentication successful"
            )
        }

        /// Refresh access token.
        /// C++ parses the response JSON and updates internal auth state
        /// atomically.
        /// - Throws: SDKException on failure
        public static func refreshToken() async throws {
            // 1. Build refresh request JSON via C++ (reads refresh_token
            //    and device_id from C++ auth state).
            guard let jsonPtr = rac_auth_build_refresh_request() else {
                throw SDKException.authentication(.invalidApiKey, "No refresh token")
            }
            let json = String(cString: jsonPtr)
            free(jsonPtr)

            logger.debug("Refreshing access token...")

            // 2. Make HTTP request
            let responseData = try await HTTP.shared.post(
                RAC_ENDPOINT_REFRESH,
                json: json,
                requiresAuth: false
            )

            // 3. Hand raw JSON to C++: parse + state update + persist.
            try handleAuthResponse(
                responseData,
                handler: rac_auth_handle_refresh_response,
                successMessage: "Token refresh successful"
            )
        }

        /// Clear authentication state
        public static func clearAuth() throws {
            // Clear C++ auth-manager state (no-op on secure storage unless
            // callbacks are registered).
            rac_auth_clear()

            // Clear Keychain (Swift owns the persistence side here).
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.accessToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.refreshToken")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.deviceId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.userId")
            try KeychainManager.shared.delete(for: "com.runanywhere.sdk.organizationId")

            logger.info("Authentication cleared")
        }

        /// Check if currently authenticated
        public static var isAuthenticated: Bool {
            rac_auth_is_authenticated()
        }

        // MARK: - Shared response handling

        /// Feed a raw JSON response body through a C++ auth response handler.
        /// Throws if the handler reports a parse/state error.
        private static func handleAuthResponse(
            _ data: Data,
            handler: (UnsafePointer<CChar>?) -> Int32,
            successMessage: String
        ) throws {
            let status: Int32 = data.withUnsafeBytes { raw -> Int32 in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                    return -1
                }
                // The HTTP body is raw JSON — null-terminate via a local copy
                // so we can pass a C string to the handler.
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count + 1)
                defer { buffer.deallocate() }
                buffer.update(from: base, count: data.count)
                buffer[data.count] = 0
                return handler(UnsafePointer(buffer))
            }

            guard status == 0 else {
                throw SDKException.authentication(
                    .authenticationFailed,
                    "Failed to parse auth response (status=\(status))"
                )
            }
            logger.info("\(successMessage)")
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
        /// - Returns: SDKException with appropriate category and message
        public static func parseAPIError(
            statusCode: Int32,
            body: Data?,
            url: String?
        ) -> SDKException {
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

            // Map status code to SDKException category
            switch statusCode {
            case 401:
                return SDKException.network(.unauthorized, message)
            case 403:
                return SDKException.network(.forbidden, message)
            case 404:
                return SDKException.network(.invalidResponse, message)
            case 408, 504:
                return SDKException.network(.timeout, message)
            case 422:
                return SDKException.network(.validationFailed, message)
            case 400..<500:
                return SDKException.network(.httpError, "Client error \(statusCode): \(message)")
            case 500..<600:
                return SDKException.network(.serverError, "Server error \(statusCode): \(message)")
            default:
                return SDKException.network(.unknown, "\(message) (status: \(statusCode))")
            }
        }
    }
}
