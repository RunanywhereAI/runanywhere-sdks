//
//  HTTPClientAdapter.swift
//  RunAnywhere SDK
//
//  P3-T4 (Swift simplification, see
//  `gaps/gaps/simplification/swift-services-duplication.md` §2).
//
//  Thin Swift bridge over the canonical `rac_http_client_*` C ABI.
//  All cross-platform HTTP policy lives in commons:
//    - `rac_http_default_headers`         → canonical SDK header list
//    - `rac_api_error_from_response`      → HTTP-status → SDKException
//

import CRACommons
import Foundation

/// HTTPClientAdapter — thin Swift bridge over `rac_http_client_*`.
public actor HTTPClientAdapter {

    public static let shared = HTTPClientAdapter()

    enum RequestTrustBoundary: Sendable {
        case controlPlane
        case externalAsset

        var followsRedirects: Bool { self == .externalAsset }
    }

    private struct Configuration: Sendable {
        let baseURL: URL
        // Nil in keyless staging: requests go out unauthenticated and the
        // backend attributes them to the PUBLIC org.
        let apiKey: String?
        let generation: UInt64
    }

    private var configuration: Configuration?
    private var nextConfigurationGeneration: UInt64 = 0
    private let logger = SDKLogger(category: "HTTPClientAdapter")

    /// Concurrent queue used to run the blocking `rac_http_client_*`
    /// request off the Swift concurrency pool.
    private static let executionQueue = DispatchQueue(
        label: "com.runanywhere.sdk.httpclient.adapter",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let defaultTimeoutMs: Int32 = 30_000

    private init() {}

    // MARK: - Configuration

    public func configure(baseURL: URL, apiKey: String) {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CppBridge.DevConfig.isUsableHTTPURL(baseURL.absoluteString) else {
            clearConfiguration()
            logger.info("HTTP adapter not configured: no usable external config")
            return
        }
        // Keyless (staging) is valid: requests go out unauthenticated.
        let usableKey = CppBridge.DevConfig.isUsableCredential(trimmedAPIKey) ? trimmedAPIKey : nil
        nextConfigurationGeneration &+= 1
        configuration = Configuration(
            baseURL: baseURL,
            apiKey: usableKey,
            generation: nextConfigurationGeneration
        )
        logger.info("HTTP adapter configured with base URL: \(baseURL.host ?? "unknown")\(usableKey == nil ? " (keyless)" : "")")
    }

    public func configure(baseURL: String, apiKey: String) {
        guard let url = URL(string: baseURL) else {
            clearConfiguration()
            logger.error("Invalid base URL: \(baseURL)")
            return
        }
        configure(baseURL: url, apiKey: apiKey)
    }

    public var isConfigured: Bool { configuration != nil }
    public var hasUsableConfiguration: Bool {
        guard let configuration else { return false }
        // A usable URL is enough — keyless staging sends unauthenticated.
        return CppBridge.DevConfig.isUsableHTTPURL(configuration.baseURL.absoluteString)
    }

    /// Clear lifetime-scoped credentials so a later SDK initialization must
    /// install its own environment instead of inheriting the previous one.
    func shutdown() {
        clearConfiguration()
        logger.debug("HTTP adapter configuration cleared")
    }

    var activeConfigurationGeneration: UInt64? { configuration?.generation }

    func configurationIsCurrent(generation: UInt64) -> Bool {
        configuration?.generation == generation
    }

    public func postRaw(_ path: String, _ payload: Data, requiresAuth: Bool) async throws -> Data {
        try await execute(method: "POST", path: path, body: payload, requiresAuth: requiresAuth)
    }

    public func getRaw(_ path: String, requiresAuth: Bool) async throws -> Data {
        try await execute(method: "GET", path: path, body: nil, requiresAuth: requiresAuth)
    }

    /// Raw-JSON-string post. Used by telemetry and auth.
    public func post(_ path: String, json: String, requiresAuth: Bool = false) async throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw SDKException(code: .validationFailed, message: "Invalid JSON string", category: .internal)
        }
        return try await postRaw(path, data, requiresAuth: requiresAuth)
    }

    // MARK: - One-shot URL fetch

    /// Fetch an absolute URL without requiring adapter configuration or auth.
    /// Intended for ancillary asset fetches (e.g. tokenizer blobs) that live
    /// outside the SDK's configured base URL.
    public static func fetchURL(_ url: URL) async throws -> Data {
        try await dispatch(
            method: "GET",
            urlString: url.absoluteString,
            apiKey: nil,
            authToken: nil,
            body: nil,
            trustBoundary: .externalAsset,
            logger: SDKLogger(category: "HTTPClientAdapter.fetchURL")
        )
    }

    // MARK: - Private Execution

    private func execute(
        method: String,
        path: String,
        body: Data?,
        requiresAuth: Bool
    ) async throws -> Data {
        guard let configuration else {
            throw SDKException(code: .serviceNotAvailable, message: "HTTP adapter not configured", category: .network)
        }
        let urlString = Self.buildURL(base: configuration.baseURL, path: path).absoluteString
        let token = try await resolveToken(
            requiresAuth: requiresAuth,
            fallbackAPIKey: configuration.apiKey
        )
        guard configurationIsCurrent(generation: configuration.generation) else {
            throw SDKException(
                code: .invalidState,
                message: "HTTP adapter configuration changed before request dispatch",
                category: .internal
            )
        }
        return try await Self.dispatch(
            method: method,
            urlString: urlString,
            apiKey: configuration.apiKey,
            authToken: token.isEmpty ? nil : token,
            body: body,
            trustBoundary: .controlPlane,
            logger: logger
        )
    }

    private func resolveToken(requiresAuth: Bool, fallbackAPIKey: String?) async throws -> String {
        if !requiresAuth { return fallbackAPIKey ?? "" }
        // `rac_auth_get_valid_token` encodes the "valid → return / expired
        // → signal refresh" handshake in one call.
        var tokenPtr: UnsafePointer<CChar>?
        var needsRefresh = false
        var status = rac_auth_get_valid_token(&tokenPtr, &needsRefresh)
        if status == 1 || needsRefresh {
            _ = try CppBridge.SdkInit.retryHTTP()
            status = rac_auth_get_valid_token(&tokenPtr, &needsRefresh)
        }
        if status == 0, let ptr = tokenPtr { return String(cString: ptr) }
        // Keyless staging: no token and no key means the request goes out
        // unauthenticated (the backend attributes it to the PUBLIC org)
        return fallbackAPIKey ?? ""
    }

    private func clearConfiguration() {
        nextConfigurationGeneration &+= 1
        configuration = nil
    }

    /// Join `base` + `path`, preserving any query string on `path`. Returns
    /// `path` as-is when it is already absolute.
    private static func buildURL(base: URL, path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? base.appendingPathComponent(path)
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
            return base.appendingPathComponent(path)
        }
        if let qIdx = path.firstIndex(of: "?") {
            components.path += String(path[..<qIdx])
            components.query = String(path[path.index(after: qIdx)...])
        } else {
            components.path += path
        }
        return components.url ?? base.appendingPathComponent(path)
    }

    // MARK: - C ABI marshalling (URLSession-flavoured continuation)

    /// Runs a single `rac_http_request_send` off the cooperative pool and
    /// maps the result back to `Data` / `SDKException`.
    private static func dispatch(
        method: String,
        urlString: String,
        apiKey: String?,
        authToken: String?,
        body: Data?,
        trustBoundary: RequestTrustBoundary,
        logger: SDKLogger
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                continuation.resume(with: Result {
                    try syncDispatch(
                        method: method,
                        urlString: urlString,
                        apiKey: apiKey,
                        authToken: authToken,
                        body: body,
                        trustBoundary: trustBoundary,
                        logger: logger
                    )
                })
            }
        }
    }

    private static func syncDispatch(
        method: String,
        urlString: String,
        apiKey: String?,
        authToken: String?,
        body: Data?,
        trustBoundary: RequestTrustBoundary,
        logger: SDKLogger
    ) throws -> Data {
        var clientHandle: OpaquePointer?
        guard rac_http_client_create(&clientHandle) == RAC_SUCCESS, let client = clientHandle else {
            throw SDKException(code: .networkError, message: "Failed to create HTTP client", category: .network)
        }
        defer { rac_http_client_destroy(client) }

        // Build header set: commons canonical list + per-request overlays.
        var headers: [String: String] = [:]
        var defaultKVs: UnsafePointer<rac_http_header_kv_t>?
        var defaultCount: Int = 0
        if rac_http_default_headers(&defaultKVs, &defaultCount) == RAC_SUCCESS, let kvs = defaultKVs {
            for index in 0..<defaultCount {
                if let name = kvs[index].name, let value = kvs[index].value {
                    headers[String(cString: name)] = String(cString: value)
                }
            }
        }
        headers["X-Platform"] = SDKConstants.platform
        if let apiKey {
            headers["apikey"] = apiKey
        }
        if let authToken {
            headers["Authorization"] = "Bearer \(authToken)"
        }

        // C-string backing storage for the duration of the request.
        guard let methodC = strdup(method), let urlC = strdup(urlString) else {
            throw SDKException(code: .networkError, message: "Out of memory building HTTP request", category: .network)
        }
        defer { free(methodC); free(urlC) }

        let pairs = headers.compactMap { name, value -> (UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)? in
            guard let nameC = strdup(name), let valueC = strdup(value) else { return nil }
            return (nameC, valueC)
        }
        defer { pairs.forEach { free($0.0); free($0.1) } }
        let kvs = pairs.map { rac_http_header_kv_t(name: UnsafePointer($0.0), value: UnsafePointer($0.1)) }

        let (rc, status, data): (rac_result_t, Int32, Data) = kvs.withUnsafeBufferPointer { kvBuf in
            send(
                client: client,
                methodC: methodC,
                urlC: urlC,
                headerKVs: kvBuf,
                body: body,
                trustBoundary: trustBoundary
            )
        }

        guard rc == RAC_SUCCESS else {
            logger.error("HTTP transport failure (rc=\(rc)) for \(method) \(urlString)")
            let code: RAErrorCode = (rc == RAC_ERROR_TIMEOUT) ? .timeout : .networkError
            throw SDKException(code: code, message: "HTTP transport error (rc=\(rc))", category: .network)
        }
        if (200...299).contains(status) { return data }
        logger.error("HTTP \(status): \(method) \(urlString)")
        throw mapAPIError(statusCode: status, body: data, url: urlString)
    }

    /// Builds the request struct, dispatches, and copies the response body
    /// into Swift-owned `Data`.
    private static func send(
        client: OpaquePointer,
        methodC: UnsafeMutablePointer<CChar>,
        urlC: UnsafeMutablePointer<CChar>,
        headerKVs: UnsafeBufferPointer<rac_http_header_kv_t>,
        body: Data?,
        trustBoundary: RequestTrustBoundary
    ) -> (rac_result_t, Int32, Data) {
        func dispatchWith(bodyBase: UnsafePointer<UInt8>?, bodyLen: Int) -> (rac_result_t, Int32, Data) {
            var request = rac_http_request_t(
                method: UnsafePointer(methodC),
                url: UnsafePointer(urlC),
                headers: headerKVs.baseAddress,
                header_count: headerKVs.count,
                body_bytes: bodyBase,
                body_len: bodyLen,
                timeout_ms: defaultTimeoutMs,
                follow_redirects: trustBoundary.followsRedirects ? RAC_TRUE : RAC_FALSE,
                expected_checksum_hex: nil
            )
            var response = rac_http_response_t()
            let result = rac_http_request_send(client, &request, &response)
            defer { rac_http_response_free(&response) }
            guard result == RAC_SUCCESS else { return (result, 0, Data()) }
            let bytes = response.body_bytes.map { Data(bytes: $0, count: response.body_len) } ?? Data()
            return (RAC_SUCCESS, response.status, bytes)
        }

        if let body, !body.isEmpty {
            return body.withUnsafeBytes { ptr in
                dispatchWith(
                    bodyBase: ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bodyLen: body.count
                )
            }
        }
        return dispatchWith(bodyBase: nil, bodyLen: 0)
    }

    /// Maps an HTTP error (status + body) to `SDKException` via commons'
    /// `rac_api_error_from_response`.
    private static func mapAPIError(statusCode: Int32, body: Data, url: String) -> SDKException {
        let bodyString = body.isEmpty ? "" : (String(data: body, encoding: .utf8) ?? "")
        var apiError = rac_api_error_t()
        let parsed = bodyString.withCString { bodyC in
            url.withCString { urlC in
                rac_api_error_from_response(statusCode, bodyC, urlC, &apiError)
            }
        }
        defer { if parsed == 0 { rac_api_error_free(&apiError) } }

        let message: String = (parsed == 0 && apiError.message != nil)
            ? String(cString: apiError.message)
            : "HTTP error \(statusCode)"

        let code: RAErrorCode
        let category: RAErrorCategory
        switch statusCode {
        case 401: (code, category) = (.authenticationFailed, .auth)
        case 403: (code, category) = (.forbidden, .auth)
        case 500...599: (code, category) = (.serverError, .network)
        default: (code, category) = (.httpError, .network)
        }
        return SDKException(code: code, message: message, category: category)
    }
}
