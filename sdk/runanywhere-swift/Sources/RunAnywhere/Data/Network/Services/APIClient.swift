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
                throw RepositoryError.syncFailure("Invalid response")
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                // Try to parse error response
                var errorMessage = "HTTP \(httpResponse.statusCode)"
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { // swiftlint:disable:this avoid_any_type
                    if let detail = errorData["detail"] as? String {
                        errorMessage = detail
                    } else if let detail = errorData["detail"] as? [[String: Any]] { // swiftlint:disable:this avoid_any_type
                        // Parse Pydantic validation errors with field location
                        let errors = detail.compactMap { error -> String? in
                            guard let msg = error["msg"] as? String else { return nil }
                            // Extract field path from loc array (e.g., ["body", "events", 0, "id"] → "events[0].id")
                            if let loc = error["loc"] as? [Any] { // swiftlint:disable:this avoid_any_type
                                let fieldPath = loc.dropFirst() // Skip "body"
                                    .map { item -> String in
                                        if let index = item as? Int {
                                            return "[\(index)]"
                                        }
                                        return String(describing: item)
                                    }
                                    .joined()
                                    .replacingOccurrences(of: "][", with: "].")  // Fix array notation
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                                return fieldPath.isEmpty ? msg : "\(fieldPath): \(msg)"
                            }
                            return msg
                        }.joined(separator: "; ")
                        errorMessage = errors.isEmpty ? errorMessage : errors
                    } else if let message = errorData["message"] as? String {
                        errorMessage = message
                    } else if let error = errorData["error"] as? String {
                        errorMessage = error
                    }
                }
                throw RepositoryError.syncFailure(errorMessage)
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
            throw RepositoryError.syncFailure("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            // Try to parse error response
            var errorMessage = "HTTP \(httpResponse.statusCode)"
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { // swiftlint:disable:this avoid_any_type
                if let detail = errorData["detail"] as? String {
                    errorMessage = detail
                } else if let detail = errorData["detail"] as? [[String: Any]] { // swiftlint:disable:this avoid_any_type
                    // Parse Pydantic validation errors with field location
                    let errors = detail.compactMap { error -> String? in
                        guard let msg = error["msg"] as? String else { return nil }
                        // Extract field path from loc array
                        if let loc = error["loc"] as? [Any] { // swiftlint:disable:this avoid_any_type
                            let fieldPath = loc.dropFirst() // Skip "body"
                                .map { item -> String in
                                    if let index = item as? Int {
                                        return "[\(index)]"
                                    }
                                    return String(describing: item)
                                }
                                .joined()
                                .replacingOccurrences(of: "][", with: "].")
                                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            return fieldPath.isEmpty ? msg : "\(fieldPath): \(msg)"
                        }
                        return msg
                    }.joined(separator: "; ")
                    errorMessage = errors.isEmpty ? errorMessage : errors
                }
            }

            throw RepositoryError.syncFailure(errorMessage)
        }

        return data
    }
}
