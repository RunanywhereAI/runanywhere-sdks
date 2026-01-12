//
//  HTTPService.swift
//  RunAnywhere SDK
//
//  Core HTTP service implementation using URLSession.
//  All network logic is centralized here.
//

import CRACommons
import Foundation

/// HTTP Service - Core network implementation
/// Centralized HTTP transport layer using URLSession
public actor HTTPService: NetworkService {

    // MARK: - Singleton

    /// Shared HTTP service instance
    public static let shared = HTTPService()

    // MARK: - Configuration

    private var session: URLSession
    private var baseURL: URL?
    private var apiKey: String?
    private let logger = SDKLogger(category: "HTTPService")

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.httpAdditionalHeaders = Self.defaultHeaders
        self.session = URLSession(configuration: config)
    }

    private static var defaultHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-SDK-Client": "RunAnywhereSDK",
            "X-SDK-Version": SDKConstants.version,
            "X-Platform": SDKConstants.platform
        ]
    }

    // MARK: - Configuration

    /// Configure HTTP service with base URL and API key
    public func configure(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        // Update session with API key header
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.httpAdditionalHeaders = Self.defaultHeaders.merging([
            "apikey": apiKey,
            "Prefer": "return=representation"
        ]) { _, new in new }
        self.session = URLSession(configuration: config)

        logger.info("HTTP service configured with base URL: \(baseURL.host ?? "unknown")")
    }

    /// Configure with URL string
    public func configure(baseURL: String, apiKey: String) {
        guard let url = URL(string: baseURL) else {
            logger.error("Invalid base URL: \(baseURL)")
            return
        }
        configure(baseURL: url, apiKey: apiKey)
    }

    /// Check if HTTP is configured
    public var isConfigured: Bool {
        baseURL != nil
    }

    /// Current base URL
    public var currentBaseURL: URL? {
        baseURL
    }

    // MARK: - NetworkService Protocol

    /// POST request with raw Data body
    public func postRaw(
        _ path: String,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data {
        // For Supabase device registration, use UPSERT (merge-duplicates) to handle existing devices
        // Supabase PostgREST requires both:
        // 1. The `Prefer: resolution=merge-duplicates` header
        // 2. The `?on_conflict=device_id` query parameter to specify the conflict column
        if path.contains(RAC_ENDPOINT_DEV_DEVICE_REGISTER) {
            // Add on_conflict query parameter to the path
            let upsertPath = path.contains("?") ? "\(path)&on_conflict=device_id" : "\(path)?on_conflict=device_id"
            return try await postRawWithHeaders(
                upsertPath,
                payload,
                requiresAuth: requiresAuth,
                additionalHeaders: ["Prefer": "resolution=merge-duplicates"]
            )
        }
        return try await postRawWithHeaders(path, payload, requiresAuth: requiresAuth)
    }

    /// POST request with raw Data body and optional additional headers
    private func postRawWithHeaders(
        _ path: String,
        _ payload: Data,
        requiresAuth: Bool,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let baseURL = baseURL else {
            throw SDKError.network(.serviceNotAvailable, "HTTP service not configured")
        }

        let url = buildURL(base: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload

        return try await executeRequest(request, requiresAuth: requiresAuth, additionalHeaders: additionalHeaders)
    }

    /// GET request with raw response
    public func getRaw(
        _ path: String,
        requiresAuth: Bool
    ) async throws -> Data {
        guard let baseURL = baseURL else {
            throw SDKError.network(.serviceNotAvailable, "HTTP service not configured")
        }

        let url = buildURL(base: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        return try await executeRequest(request, requiresAuth: requiresAuth)
    }

    // MARK: - Convenience Methods

    /// POST with JSON string body
    public func post(_ path: String, json: String, requiresAuth: Bool = false) async throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw SDKError.general(.validationFailed, "Invalid JSON string")
        }
        return try await postRaw(path, data, requiresAuth: requiresAuth)
    }

    /// POST with Encodable payload
    public func post<T: Encodable>(_ path: String, payload: T, requiresAuth: Bool = true) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return try await postRaw(path, data, requiresAuth: requiresAuth)
    }

    /// DELETE request
    public func delete(_ path: String, requiresAuth: Bool = true) async throws -> Data {
        guard let baseURL = baseURL else {
            throw SDKError.network(.serviceNotAvailable, "HTTP service not configured")
        }

        let url = buildURL(base: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        return try await executeRequest(request, requiresAuth: requiresAuth)
    }

    /// PUT request
    public func put(_ path: String, _ payload: Data, requiresAuth: Bool = true) async throws -> Data {
        guard let baseURL = baseURL else {
            throw SDKError.network(.serviceNotAvailable, "HTTP service not configured")
        }

        let url = buildURL(base: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = payload

        return try await executeRequest(request, requiresAuth: requiresAuth)
    }

    // MARK: - Private Implementation

    private func buildURL(base: URL, path: String) -> URL {
        // Handle paths that start with "/" vs full URLs
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? base.appendingPathComponent(path)
        }

        // Check if path contains query parameters
        if path.contains("?") {
            // Split path and query parameters
            let components = path.split(separator: "?", maxSplits: 1)
            let pathPart = String(components[0])
            let queryPart = String(components[1])

            // Build URL with query parameters using URLComponents
            guard var urlComponents = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
                return base.appendingPathComponent(path)
            }
            let existingPath = urlComponents.path
            urlComponents.path = existingPath + pathPart
            urlComponents.query = queryPart

            return urlComponents.url ?? base.appendingPathComponent(path)
        }

        return base.appendingPathComponent(path)
    }

    private func executeRequest(_ request: URLRequest, requiresAuth: Bool, additionalHeaders: [String: String] = [:]) async throws -> Data {
        var request = request

        // Add additional headers if provided
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add authorization header
        let token = try await resolveToken(requiresAuth: requiresAuth)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Execute request
        let (data, response) = try await session.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.network(.invalidResponse, "Invalid HTTP response")
        }

        // Check status code
        // For device registration, 409 (Conflict) means device already exists, which is fine
        let isDeviceRegistration = request.url?.absoluteString.contains(RAC_ENDPOINT_DEV_DEVICE_REGISTER) ?? false
        let isSuccess = (200...299).contains(httpResponse.statusCode) || (isDeviceRegistration && httpResponse.statusCode == 409)

        guard isSuccess else {
            let error = parseHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                url: request.url?.absoluteString ?? "unknown"
            )
            logger.error("HTTP \(httpResponse.statusCode): \(request.url?.absoluteString ?? "unknown")")
            throw error
        }

        // Log 409 as info for device registration (device already exists)
        if isDeviceRegistration && httpResponse.statusCode == 409 {
            logger.info("Device already registered (409) - treating as success")
        }

        return data
    }

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
            // Fallback to API key if no OAuth token available
            // This supports API key-only authentication for production mode
            if let key = apiKey, !key.isEmpty {
                return key
            }
            throw SDKError.authentication(.authenticationFailed, "No valid authentication token")
        }
        // Use API key for non-auth requests
        return apiKey ?? ""
    }

    private func parseHTTPError(statusCode: Int, data: Data, url _: String) -> SDKError {
        // Try to parse error message from response body
        var errorMessage = "HTTP error \(statusCode)"

        // JSONSerialization returns heterogeneous dictionary for parsing unknown JSON error responses
        // swiftlint:disable:next avoid_any_type
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String {
                errorMessage = message
            } else if let error = json["error"] as? String {
                errorMessage = error
            } else if let hint = json["hint"] as? String {
                errorMessage = "\(errorMessage): \(hint)"
            }
        }

        switch statusCode {
        case 400:
            return SDKError.network(.httpError, "Bad request: \(errorMessage)")
        case 401:
            return SDKError.authentication(.authenticationFailed, errorMessage)
        case 403:
            return SDKError.authentication(.forbidden, errorMessage)
        case 404:
            return SDKError.network(.httpError, "Not found: \(errorMessage)")
        case 429:
            return SDKError.network(.httpError, "Rate limited: \(errorMessage)")
        case 500...599:
            return SDKError.network(.serverError, "Server error (\(statusCode)): \(errorMessage)")
        default:
            return SDKError.network(.httpError, "HTTP \(statusCode): \(errorMessage)")
        }
    }
}
