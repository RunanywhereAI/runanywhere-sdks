//
//  CppBridge+HTTP.swift
//  RunAnywhere SDK
//
//  HTTP transport bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - HTTP Bridge (Unified HTTP Transport)

extension CppBridge {

    /// HTTP transport bridge - unified URLSession wrapper
    /// Conforms to NetworkService for compatibility with existing code
    /// Replaces APIClient for all HTTP operations
    public actor HTTP: NetworkService {

        /// Shared HTTP instance
        public static let shared = HTTP()

        private var session: URLSession
        private var baseURL: URL?
        private var apiKey: String?
        private let logger = SDKLogger(category: "CppBridge.HTTP")

        private init() {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.httpAdditionalHeaders = [
                "Content-Type": "application/json",
                "X-SDK-Client": "RunAnywhereSDK",
                "X-SDK-Version": SDKConstants.version,
                "X-Platform": SDKConstants.platform
            ]
            self.session = URLSession(configuration: config)
        }

        /// Configure HTTP with base URL and API key
        public func configure(baseURL: URL, apiKey: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey

            // Update session with API key header
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.httpAdditionalHeaders = [
                "Content-Type": "application/json",
                "X-SDK-Client": "RunAnywhereSDK",
                "X-SDK-Version": SDKConstants.version,
                "X-Platform": SDKConstants.platform,
                "apikey": apiKey,
                "Prefer": "return=representation"
            ]
            self.session = URLSession(configuration: config)
        }

        /// Check if HTTP is configured
        public var isConfigured: Bool {
            baseURL != nil
        }

        // MARK: - NetworkService Protocol

        /// POST request with raw Data body (NetworkService protocol)
        public func postRaw(
            _ path: String,
            _ payload: Data,
            requiresAuth: Bool
        ) async throws -> Data {
            guard let baseURL = baseURL else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payload

            let token = try await resolveToken(requiresAuth: requiresAuth)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            return try await execute(request, url: url)
        }

        /// GET request with raw response (NetworkService protocol)
        public func getRaw(
            _ path: String,
            requiresAuth: Bool
        ) async throws -> Data {
            guard let baseURL = baseURL else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let token = try await resolveToken(requiresAuth: requiresAuth)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            return try await execute(request, url: url)
        }

        // MARK: - JSON Convenience Methods

        /// POST request with JSON string body
        public func post(_ path: String, json: String, requiresAuth: Bool = false) async throws -> Data {
            guard let data = json.data(using: .utf8) else {
                throw SDKError.general(.validationFailed, "Invalid JSON string")
            }
            return try await postRaw(path, data, requiresAuth: requiresAuth)
        }

        // MARK: - Private Helpers

        private func resolveToken(requiresAuth: Bool) async throws -> String {
            if requiresAuth {
                // Get token from C++ state, refreshing if needed
                if let token = CppBridge.State.accessToken, !CppBridge.State.tokenNeedsRefresh {
                    return token
                }
                // Try refresh if we have refresh token
                if CppBridge.State.refreshToken != nil {
                    try await CppBridge.Auth.refreshToken()
                    if let token = CppBridge.State.accessToken {
                        return token
                    }
                }
                throw SDKError.authentication(.authenticationFailed, "No valid token")
            }
            // Use API key for non-auth requests
            return apiKey ?? ""
        }

        private func execute(_ request: URLRequest, url: URL) async throws -> Data {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SDKError.network(.invalidResponse, "Invalid HTTP response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let error = CppBridge.Auth.parseAPIError(
                    statusCode: Int32(httpResponse.statusCode),
                    body: data,
                    url: url.absoluteString
                )
                logger.error("HTTP \(httpResponse.statusCode): \(url)")
                throw error
            }

            return data
        }
    }
}
