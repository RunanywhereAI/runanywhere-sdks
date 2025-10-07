import Foundation
import Pulse

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

    // MARK: - NetworkService Protocol Implementation

    /// Perform a raw POST request
    public func postRaw(
        _ endpoint: APIEndpoint,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data {
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
        request.httpBody = payload

        // Set authorization header
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if endpoint == .authenticate {
            // For authentication endpoint, API key is in the request body, not header
            // No authorization header needed for authentication endpoint
        }

        logger.debug("POST request to: \(endpoint.path)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.syncFailure("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            // Try to parse error response
            var errorMessage = "HTTP \(httpResponse.statusCode)"

            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = errorData["detail"] as? String {
                    errorMessage = detail
                } else if let detail = errorData["detail"] as? [[String: Any]] {
                    let errors = detail.compactMap { $0["msg"] as? String }.joined(separator: ", ")
                    errorMessage = errors.isEmpty ? errorMessage : errors
                } else if let message = errorData["message"] as? String {
                    errorMessage = message
                } else if let error = errorData["error"] as? String {
                    errorMessage = error
                }
            }

            logger.error("API error: \(httpResponse.statusCode)", metadata: [
                "url": url.absoluteString,
                "method": "POST",
                "statusCode": httpResponse.statusCode,
                "endpoint": endpoint.path
            ])
            throw RepositoryError.syncFailure(errorMessage)
        }

        return data
    }

    /// Perform a raw GET request
    public func getRaw(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool
    ) async throws -> Data {
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
            // Try to parse error response
            var errorMessage = "HTTP \(httpResponse.statusCode)"
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = errorData["detail"] as? String {
                    errorMessage = detail
                } else if let detail = errorData["detail"] as? [[String: Any]] {
                    let errors = detail.compactMap { $0["msg"] as? String }.joined(separator: ", ")
                    errorMessage = errors.isEmpty ? errorMessage : errors
                }
            }

            logger.error("API error: \(httpResponse.statusCode)", metadata: [
                "url": url.absoluteString,
                "method": "GET",
                "statusCode": httpResponse.statusCode,
                "endpoint": endpoint.path
            ])
            throw RepositoryError.syncFailure(errorMessage)
        }

        return data
    }
}
