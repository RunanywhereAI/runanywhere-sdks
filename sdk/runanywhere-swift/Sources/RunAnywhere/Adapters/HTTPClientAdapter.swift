//
//  HTTPClientAdapter.swift
//  RunAnywhere SDK
//
//  Swift-side actor wrapping the canonical `rac_http_client_*` C ABI
//  (curl-backed, shared across all SDKs). Drop-in replacement for the
//  legacy URLSession-based `HTTPService`. All platform SDKs now route
//  HTTP transport through this single C implementation.
//

import CRACommons
import Foundation

/// HTTPClientAdapter — thin Swift bridge over `rac_http_client_*`.
///
/// Preserves the public surface of the old `HTTPService` actor so
/// call sites migrate unchanged (see `typealias HTTPService =
/// HTTPClientAdapter` below).
public actor HTTPClientAdapter: NetworkService {

    // MARK: - Singleton

    public static let shared = HTTPClientAdapter()

    // MARK: - State

    private var baseURL: URL?
    private var apiKey: String?
    private let logger = SDKLogger(category: "HTTPClientAdapter")

    /// Serial queue used to run the blocking curl request off the
    /// Swift concurrency pool.
    private static let executionQueue = DispatchQueue(
        label: "com.runanywhere.sdk.httpclient.adapter",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    public func configure(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        logger.info("HTTP adapter configured with base URL: \(baseURL.host ?? "unknown")")
    }

    public func configure(baseURL: String, apiKey: String) {
        guard let url = URL(string: baseURL) else {
            logger.error("Invalid base URL: \(baseURL)")
            return
        }
        configure(baseURL: url, apiKey: apiKey)
    }

    public var isConfigured: Bool { baseURL != nil }

    public var currentBaseURL: URL? { baseURL }

    // MARK: - NetworkService Protocol

    public func postRaw(
        _ path: String,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data {
        // Supabase device registration uses UPSERT semantics — both
        // the `on_conflict` query param and the merge-duplicates
        // Prefer header are required.
        if path.contains(RAC_ENDPOINT_DEV_DEVICE_REGISTER) {
            let upsertPath = path.contains("?")
                ? "\(path)&on_conflict=device_id"
                : "\(path)?on_conflict=device_id"
            return try await execute(
                method: "POST",
                path: upsertPath,
                body: payload,
                requiresAuth: requiresAuth,
                additionalHeaders: ["Prefer": "resolution=merge-duplicates"]
            )
        }
        return try await execute(method: "POST", path: path, body: payload, requiresAuth: requiresAuth)
    }

    public func getRaw(
        _ path: String,
        requiresAuth: Bool
    ) async throws -> Data {
        try await execute(method: "GET", path: path, body: nil, requiresAuth: requiresAuth)
    }

    // MARK: - Convenience Methods

    public func post(_ path: String, json: String, requiresAuth: Bool = false) async throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw SDKError.general(.validationFailed, "Invalid JSON string")
        }
        return try await postRaw(path, data, requiresAuth: requiresAuth)
    }

    public func post<T: Encodable>(_ path: String, payload: T, requiresAuth: Bool = true) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return try await postRaw(path, data, requiresAuth: requiresAuth)
    }

    public func delete(_ path: String, requiresAuth: Bool = true) async throws -> Data {
        try await execute(method: "DELETE", path: path, body: nil, requiresAuth: requiresAuth)
    }

    public func put(_ path: String, _ payload: Data, requiresAuth: Bool = true) async throws -> Data {
        try await execute(method: "PUT", path: path, body: payload, requiresAuth: requiresAuth)
    }

    // MARK: - One-shot URL fetch

    /// Fetch an absolute URL without requiring adapter configuration
    /// or auth. Intended for ancillary asset fetches (e.g. tokenizer
    /// blobs) that live outside the SDK's configured base URL.
    public static func fetchURL(_ url: URL, timeoutMs: Int32 = 30_000) async throws -> Data {
        let fetchLogger = SDKLogger(category: "HTTPClientAdapter.fetchURL")
        return try await perform(
            method: "GET",
            urlString: url.absoluteString,
            headers: defaultHeaders,
            body: nil,
            logger: fetchLogger,
            isDeviceRegistration: false
        )
    }

    // MARK: - Private Execution

    private func execute(
        method: String,
        path: String,
        body: Data?,
        requiresAuth: Bool,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let baseURL = baseURL else {
            throw SDKError.network(.serviceNotAvailable, "HTTP adapter not configured")
        }

        let url = buildURL(base: baseURL, path: path)
        var headers = Self.defaultHeaders
        if let apiKey = apiKey {
            headers["apikey"] = apiKey
            // Supabase PostgREST default behaviour — include the
            // inserted/updated row in the response body.
            headers["Prefer"] = "return=representation"
        }
        let token = try await resolveToken(requiresAuth: requiresAuth)
        if !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        for (key, value) in additionalHeaders {
            headers[key] = value
        }

        let urlString = url.absoluteString
        let isDeviceRegistration = urlString.contains(RAC_ENDPOINT_DEV_DEVICE_REGISTER)

        let logger = self.logger
        return try await Self.perform(
            method: method,
            urlString: urlString,
            headers: headers,
            body: body,
            logger: logger,
            isDeviceRegistration: isDeviceRegistration
        )
    }

    private func resolveToken(requiresAuth: Bool) async throws -> String {
        if requiresAuth {
            // Prefer OAuth token from C++ auth state.
            if let token = CppBridge.State.accessToken, !CppBridge.State.tokenNeedsRefresh {
                return token
            }
            if CppBridge.State.refreshToken != nil {
                try await CppBridge.Auth.refreshToken()
                if let token = CppBridge.State.accessToken {
                    return token
                }
            }
            // Fall back to API-key-only auth (production mode).
            if let key = apiKey, !key.isEmpty {
                return key
            }
            throw SDKError.authentication(.authenticationFailed, "No valid authentication token")
        }
        return apiKey ?? ""
    }

    private func buildURL(base: URL, path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? base.appendingPathComponent(path)
        }

        if path.contains("?") {
            let components = path.split(separator: "?", maxSplits: 1)
            let pathPart = String(components[0])
            let queryPart = String(components[1])

            guard var urlComponents = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
                return base.appendingPathComponent(path)
            }
            urlComponents.path = urlComponents.path + pathPart
            urlComponents.query = queryPart
            return urlComponents.url ?? base.appendingPathComponent(path)
        }

        return base.appendingPathComponent(path)
    }

    // MARK: - Static helpers

    private static var defaultHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-SDK-Client": "RunAnywhereSDK",
            "X-SDK-Version": SDKConstants.version,
            "X-Platform": SDKConstants.platform
        ]
    }

    /// Default request timeout (matches legacy HTTPService: 30s).
    private static let defaultTimeoutMs: Int32 = 30_000

    /// Run the blocking curl call on a background queue and surface
    /// the result as a Swift async value.
    private static func perform(
        method: String,
        urlString: String,
        headers: [String: String],
        body: Data?,
        logger: SDKLogger,
        isDeviceRegistration: Bool
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                do {
                    let data = try syncPerform(
                        method: method,
                        urlString: urlString,
                        headers: headers,
                        body: body,
                        logger: logger,
                        isDeviceRegistration: isDeviceRegistration
                    )
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func syncPerform(
        method: String,
        urlString: String,
        headers: [String: String],
        body: Data?,
        logger: SDKLogger,
        isDeviceRegistration: Bool
    ) throws -> Data {
        // Build client (one libcurl easy handle per request — simple,
        // thread-safe, no pool contention).
        var clientHandle: OpaquePointer?
        let createResult = rac_http_client_create(&clientHandle)
        guard createResult == RAC_SUCCESS, let client = clientHandle else {
            throw SDKError.network(.networkError, "Failed to create HTTP client (rc=\(createResult))")
        }
        defer { rac_http_client_destroy(client) }

        // Keep C-string backing storage alive for the duration of the
        // call. libcurl does copy into its slist internally but the
        // request struct carries raw `const char*` pointers.
        let methodCString = strdup(method)
        let urlCString = strdup(urlString)
        defer {
            free(methodCString)
            free(urlCString)
        }
        guard let methodCString = methodCString, let urlCString = urlCString else {
            throw SDKError.network(.networkError, "Out of memory building HTTP request")
        }

        let headerPairs: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] =
            headers.compactMap { name, value in
                guard let n = strdup(name), let v = strdup(value) else { return nil }
                return (n, v)
            }
        defer {
            for (n, v) in headerPairs {
                free(n)
                free(v)
            }
        }

        let headerKVs: [rac_http_header_kv_t] = headerPairs.map { name, value in
            rac_http_header_kv_t(name: UnsafePointer(name), value: UnsafePointer(value))
        }

        var responseData: Data = Data()
        var responseStatus: Int32 = 0

        let sendResult: rac_result_t
        if let body = body, !body.isEmpty {
            (sendResult, responseStatus, responseData) = body.withUnsafeBytes { bodyPtr -> (rac_result_t, Int32, Data) in
                sendWithHeaders(
                    client: client,
                    methodC: methodCString,
                    urlC: urlCString,
                    headerKVs: headerKVs,
                    bodyBase: bodyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bodyLen: body.count
                )
            }
        } else {
            (sendResult, responseStatus, responseData) = sendWithHeaders(
                client: client,
                methodC: methodCString,
                urlC: urlCString,
                headerKVs: headerKVs,
                bodyBase: nil,
                bodyLen: 0
            )
        }

        guard sendResult == RAC_SUCCESS else {
            let message = transportErrorMessage(result: sendResult)
            logger.error("HTTP transport failure (rc=\(sendResult)) for \(method) \(urlString)")
            throw networkError(forResult: sendResult, message: message)
        }

        let isSuccess = (200...299).contains(responseStatus)
            || (isDeviceRegistration && responseStatus == 409)

        guard isSuccess else {
            logger.error("HTTP \(responseStatus): \(method) \(urlString)")
            throw parseHTTPError(
                statusCode: Int(responseStatus),
                data: responseData,
                url: urlString
            )
        }

        if isDeviceRegistration && responseStatus == 409 {
            logger.info("Device already registered (409) - treating as success")
        }

        return responseData
    }

    private static func sendWithHeaders(
        client: OpaquePointer,
        methodC: UnsafeMutablePointer<CChar>,
        urlC: UnsafeMutablePointer<CChar>,
        headerKVs: [rac_http_header_kv_t],
        bodyBase: UnsafePointer<UInt8>?,
        bodyLen: Int
    ) -> (rac_result_t, Int32, Data) {
        headerKVs.withUnsafeBufferPointer { kvBuffer in
            var request = rac_http_request_t(
                method: UnsafePointer(methodC),
                url: UnsafePointer(urlC),
                headers: kvBuffer.baseAddress,
                header_count: kvBuffer.count,
                body_bytes: bodyBase,
                body_len: bodyLen,
                timeout_ms: defaultTimeoutMs,
                follow_redirects: RAC_TRUE,
                expected_checksum_hex: nil
            )

            var response = rac_http_response_t()
            let result = rac_http_request_send(client, &request, &response)
            defer { rac_http_response_free(&response) }

            if result != RAC_SUCCESS {
                return (result, 0, Data())
            }

            var body = Data()
            if let bytes = response.body_bytes, response.body_len > 0 {
                body = Data(bytes: bytes, count: response.body_len)
            }
            return (RAC_SUCCESS, response.status, body)
        }
    }

    private static func transportErrorMessage(result: rac_result_t) -> String {
        switch result {
        case RAC_ERROR_NETWORK_ERROR:
            return "Network error"
        case RAC_ERROR_TIMEOUT:
            return "Request timed out"
        case RAC_ERROR_CANCELLED:
            return "Request cancelled"
        case RAC_ERROR_INVALID_ARGUMENT:
            return "Invalid HTTP request"
        case RAC_ERROR_OUT_OF_MEMORY:
            return "Out of memory"
        default:
            return "HTTP transport error (rc=\(result))"
        }
    }

    private static func networkError(forResult result: rac_result_t, message: String) -> SDKError {
        switch result {
        case RAC_ERROR_TIMEOUT:
            return SDKError.network(.timeout, message)
        case RAC_ERROR_CANCELLED:
            return SDKError.network(.networkError, message)
        default:
            return SDKError.network(.networkError, message)
        }
    }

    private static func parseHTTPError(statusCode: Int, data: Data, url _: String) -> SDKError {
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

// MARK: - Legacy alias

/// Source-compatibility alias for existing call sites that reference
/// the pre-migration `HTTPService` type (e.g. `CppBridge+HTTP` and the
/// `NetworkService` conformance).
public typealias HTTPService = HTTPClientAdapter
