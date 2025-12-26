import Foundation

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

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.network(.invalidResponse, "Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.sdkErrorFromHTTPStatus(httpResponse.statusCode, data: data)
        }

        return data
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
            throw SDKError.network(.invalidResponse, "Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.sdkErrorFromHTTPStatus(httpResponse.statusCode, data: data)
        }

        return data
    }

    // MARK: - Private Helpers

    /// Convert HTTP status code and response data to SDKError
    private static func sdkErrorFromHTTPStatus(_ statusCode: Int, data: Data?) -> SDKError {
        // Try to parse error response for better message
        var message: String?
        if let data = data,
           let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            if let detail = errorResponse.detail {
                switch detail {
                case .message(let msg):
                    message = msg
                case .validationErrors(let errors):
                    let messages = errors.map { $0.formattedMessage }
                    message = messages.joined(separator: "; ")
                }
            } else if let msg = errorResponse.message {
                message = msg
            } else if let err = errorResponse.error {
                message = err
            }
        }

        switch statusCode {
        case 401:
            return SDKError.network(.unauthorized, message ?? "Authentication required")
        case 403:
            return SDKError.network(.forbidden, message ?? "Access denied")
        case 404:
            return SDKError.network(.invalidResponse, message ?? "Resource not found")
        case 408, 504:
            return SDKError.network(.timeout, message ?? "Request timed out")
        case 422:
            return SDKError.network(.validationFailed, message ?? "Validation failed")
        case 400..<500:
            return SDKError.network(.httpError, "Client error \(statusCode): \(message ?? "Unknown error")")
        case 500..<600:
            return SDKError.network(.serverError, "Server error \(statusCode): \(message ?? "Unknown error")")
        default:
            return SDKError.network(.unknown, message ?? "Unknown error with status code \(statusCode)")
        }
    }
}
