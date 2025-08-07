import Foundation
import Pulse

/// Simple API client for cloud sync operations
public actor APIClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let logger = SDKLogger(category: "APIClient")

    // MARK: - Initialization

    public init(baseURL: String, apiKey: String) {
        self.baseURL = URL(string: baseURL)!
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "X-SDK-Client": "RunAnywhereSDK"
        ]

        // Configure URLSession with Pulse proxy for automatic network logging
        self.session = URLSession(
            configuration: config,
            delegate: URLSessionProxyDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Public Methods

    /// Perform a POST request
    public func post<T: Encodable, R: Decodable>(
        _ endpoint: APIEndpoint,
        _ payload: T
    ) async throws -> R {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)

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
        _ endpoint: APIEndpoint
    ) async throws -> R {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

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
