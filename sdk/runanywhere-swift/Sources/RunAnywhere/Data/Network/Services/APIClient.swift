import Foundation
import Pulse

/// Production API client for backend operations
/// Implements NetworkService protocol for real network calls
public actor APIClient: NetworkService {
    private let baseURL: URL
    private let apiKey: String
    private var authService: AuthenticationService?
    private let session: URLSession

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

        // Configure URLSession with Pulse proxy for automatic network logging
        self.session = URLSession(
            configuration: config,
            delegate: URLSessionProxyDelegate(),
            delegateQueue: nil
        )
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
        let token: String

        if requiresAuth {
            if let authService = authService {
                token = try await authService.getAccessToken()
            } else {
                // No auth service - use API key as bearer token (Supabase development mode)
                token = apiKey
            }
        } else {
            // For non-auth requests, still use API key as bearer for Supabase compatibility
            token = apiKey
        }

        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload

        // Set authorization header (always set for Supabase compatibility)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(message: "Invalid HTTP response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.from(statusCode: httpResponse.statusCode, data: data)
            }

            return data
        }
    }

    /// Perform a raw GET request
    public func getRaw(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool
    ) async throws -> Data {
        let token: String
        if requiresAuth {
            if let authService = authService {
                token = try await authService.getAccessToken()
            } else {
                // No auth service - use API key as bearer token (Supabase development mode)
                token = apiKey
            }
        } else {
            // For non-auth requests, still use API key as bearer for Supabase compatibility
            token = apiKey
        }

        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Set authorization header (always set for Supabase compatibility)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(message: "Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.from(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }
}
