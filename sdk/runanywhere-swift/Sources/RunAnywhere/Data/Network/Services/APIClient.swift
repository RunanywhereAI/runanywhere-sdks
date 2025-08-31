import Foundation
import Pulse

/// Simple API client for backend operations
public actor APIClient {
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
            "X-Platform": SDKConstants.platform
        ]

        // Configure URLSession with Pulse proxy for automatic network logging
        self.session = URLSession(
            configuration: config,
            delegate: URLSessionProxyDelegate(),
            delegateQueue: nil
        )

        logger.info("APIClient initialized with baseURL: \(baseURL.absoluteString)")
    }

    // MARK: - Public Methods

    /// Set the authentication service (called after AuthenticationService is created)
    public func setAuthenticationService(_ authService: AuthenticationService) {
        self.authService = authService
    }

    /// Perform a POST request
    public func post<T: Encodable, R: Decodable>(
        _ endpoint: APIEndpoint,
        _ payload: T,
        requiresAuth: Bool = true
    ) async throws -> R {
        let token: String?
        if requiresAuth {
            guard let authService = authService else {
                throw SDKError.notInitialized
            }
            token = try await authService.getAccessToken()
        } else {
            token = nil
        }

        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)

        // Set authorization header
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if endpoint == .authenticate {
            // For authentication endpoint, use API key
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        logger.debug("POST request to: \(endpoint.path)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.syncFailure("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("API error: \(httpResponse.statusCode)", metadata: [
                "url": url.absoluteString,
                "method": "POST",
                "statusCode": httpResponse.statusCode,
                "endpoint": endpoint.path
            ])
            throw RepositoryError.syncFailure("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    /// Perform a GET request
    public func get<R: Decodable>(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool = true
    ) async throws -> R {
        let token: String?
        if requiresAuth {
            guard let authService = authService else {
                throw SDKError.notInitialized
            }
            token = try await authService.getAccessToken()
        } else {
            token = nil
        }

        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Set authorization header
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logger.debug("GET request to: \(endpoint.path)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.syncFailure("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("API error: \(httpResponse.statusCode)", metadata: [
                "url": url.absoluteString,
                "method": "GET",
                "statusCode": httpResponse.statusCode,
                "endpoint": endpoint.path
            ])
            throw RepositoryError.syncFailure("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(R.self, from: data)
    }
}
