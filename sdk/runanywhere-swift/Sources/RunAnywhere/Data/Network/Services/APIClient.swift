import Foundation

/// Production API client for backend operations
/// Implements NetworkService protocol for real network calls
public actor APIClient: NetworkService {
    private let baseURL: URL
    private let apiKey: String
    private var authService: AuthenticationService?
    private let session: URLSession
    private let logger = SDKLogger(category: "APIClient")

    // MARK: - Initialization

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.authService = nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "X-SDK-Client": "RunAnywhereSDK",
            "X-SDK-Version": SDKConstants.version,
            "X-Platform": SDKConstants.platform,
            // Supabase-compatible headers (also works with standard backends)
            "apikey": apiKey,
            // Supabase: Request to return the created/updated row
            "Prefer": "return=representation"
        ]

        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Set the authentication service (called after AuthenticationService is created)
    public func setAuthenticationService(_ authService: AuthenticationService) {
        self.authService = authService
    }

    // MARK: - NetworkService Protocol Implementation

    /// Perform a raw POST request
    public func postRaw(
        _ endpoint: APIEndpoint,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data {
        let token = try await resolveToken(requiresAuth: requiresAuth)
        let url = baseURL.appendingPathComponent(endpoint.path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await executeRequest(request, url: url)
    }

    /// Perform a raw GET request
    public func getRaw(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool
    ) async throws -> Data {
        let token = try await resolveToken(requiresAuth: requiresAuth)
        let url = baseURL.appendingPathComponent(endpoint.path)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await executeRequest(request, url: url)
    }

    // MARK: - Private Helpers

    private func resolveToken(requiresAuth: Bool) async throws -> String {
        if requiresAuth, let authService = authService {
            return try await authService.getAccessToken()
        }
        // Use API key as bearer token (Supabase compatibility)
        return apiKey
    }

    private func executeRequest(_ request: URLRequest, url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = SDKError.network(.invalidResponse, "Invalid HTTP response")
            emitErrorEvent(error: error, url: url, statusCode: nil, data: nil)
            throw error
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorInfo = APIErrorInfo(
                data: data,
                statusCode: httpResponse.statusCode,
                requestURL: url.absoluteString
            )
            let error = errorInfo.toSDKError(statusCode: httpResponse.statusCode)

            // Emit error event with full context for consumer logging
            emitErrorEvent(
                error: error,
                url: url,
                statusCode: httpResponse.statusCode,
                data: data
            )

            // Log detailed error info for debugging
            logger.error("API request failed: \(errorInfo.debugDescription)")

            throw error
        }

        return data
    }

    /// Emit an error event to both EventBus (for consumers) and analytics
    private func emitErrorEvent(error: SDKError, url: URL, statusCode: Int?, data: Data?) {
        let responseBody = data.flatMap { String(data: $0, encoding: .utf8) }

        let errorEvent = SDKErrorEvent.networkError(
            error: error,
            url: url.absoluteString,
            statusCode: statusCode,
            responseBody: responseBody
        )

        EventPublisher.shared.track(errorEvent)
    }
}
