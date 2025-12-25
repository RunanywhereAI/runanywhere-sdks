//
//  APIError.swift
//  RunAnywhere SDK
//
//  Type-safe API error handling matching backend error formats
//

import Foundation

// MARK: - API Error

/// Comprehensive API error type for network operations
public enum APIError: LocalizedError, Sendable {
    // MARK: - HTTP Errors

    /// Client error (4xx)
    case clientError(statusCode: Int, message: String, code: String?)

    /// Server error (5xx)
    case serverError(statusCode: Int, message: String, code: String?)

    /// Validation error (422 - Pydantic validation failures)
    case validationError(statusCode: Int, errors: [ValidationError], code: String?)

    // MARK: - Authentication Errors

    /// Unauthorized (401)
    case unauthorized(message: String)

    /// Forbidden (403)
    case forbidden(message: String)

    // MARK: - Network Errors

    /// Network unavailable
    case networkUnavailable

    /// Request timeout
    case timeout(message: String?)

    /// Invalid response format
    case invalidResponse(message: String)

    /// Decoding error
    case decodingFailed(Error)

    /// Unknown error
    case unknown(statusCode: Int, message: String?)

    // MARK: - Factory Methods

    /// Create appropriate error from HTTP status code and response data
    public static func from(
        statusCode: Int,
        data: Data?,
        underlyingError: Error? = nil
    ) -> APIError {
        // Try to parse error response
        if let data = data,
           let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return errorResponse.toAPIError(statusCode: statusCode)
        }

        // Fallback to status-code based error
        switch statusCode {
        case 401:
            return .unauthorized(message: "Authentication required")
        case 403:
            return .forbidden(message: "Access denied")
        case 404:
            return .clientError(statusCode: 404, message: "Resource not found", code: nil)
        case 408, 504:
            return .timeout(message: "Request timed out")
        case 422:
            return .validationError(statusCode: 422, errors: [], code: nil)
        case 400..<500:
            return .clientError(statusCode: statusCode, message: "Client error", code: nil)
        case 500..<600:
            return .serverError(statusCode: statusCode, message: "Server error", code: nil)
        default:
            return .unknown(statusCode: statusCode, message: nil)
        }
    }

    // MARK: - Properties

    /// HTTP status code if applicable
    public var statusCode: Int? {
        switch self {
        case .clientError(let code, _, _),
             .serverError(let code, _, _),
             .validationError(let code, _, _),
             .unknown(let code, _):
            return code
        case .unauthorized:
            return 401
        case .forbidden:
            return 403
        default:
            return nil
        }
    }

    /// Error code from backend
    public var code: String? {
        switch self {
        case .clientError(_, _, let code),
             .serverError(_, _, let code),
             .validationError(_, _, let code):
            return code
        default:
            return nil
        }
    }

    /// Whether this is a retryable error
    public var isRetryable: Bool {
        switch self {
        case .serverError(let statusCode, _, _):
            return statusCode >= 500
        case .timeout, .networkUnavailable:
            return true
        default:
            return false
        }
    }

    /// Whether this requires re-authentication
    public var requiresReauth: Bool {
        switch self {
        case .unauthorized:
            return true
        default:
            return false
        }
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .clientError(let statusCode, let message, _):
            return "Client error (\(statusCode)): \(message)"
        case .serverError(let statusCode, let message, _):
            return "Server error (\(statusCode)): \(message)"
        case .validationError(_, let errors, _):
            if errors.isEmpty {
                return "Validation failed"
            }
            let messages = errors.map { $0.formattedMessage }
            return "Validation failed: \(messages.joined(separator: "; "))"
        case .unauthorized(let message):
            return "Unauthorized: \(message)"
        case .forbidden(let message):
            return "Forbidden: \(message)"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .timeout(let message):
            return message ?? "Request timed out"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unknown(let statusCode, let message):
            if let message = message {
                return "Error (\(statusCode)): \(message)"
            }
            return "Unknown error (\(statusCode))"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return "Please check your credentials and try again."
        case .forbidden:
            return "You don't have permission to access this resource."
        case .networkUnavailable, .timeout:
            return "Check your internet connection and try again."
        case .validationError:
            return "Please check your input and try again."
        case .serverError:
            return "The server encountered an error. Please try again later."
        default:
            return nil
        }
    }
}

// MARK: - Convert to RunAnywhereError

public extension APIError {
    /// Convert to RunAnywhereError for public API
    func toRunAnywhereError() -> RunAnywhereError {
        switch self {
        case .unauthorized(let message):
            return .authenticationFailed(message)
        case .forbidden(let message):
            return .authenticationFailed(message)
        case .networkUnavailable:
            return .networkUnavailable
        case .timeout(let message):
            return .timeout(message ?? "Request timed out")
        case .serverError(_, let message, _):
            return .serverError(message)
        case .clientError(_, let message, _):
            return .networkError(message)
        case .validationError(_, let errors, _):
            let message = errors.map { $0.formattedMessage }.joined(separator: "; ")
            return .validationFailed(message.isEmpty ? "Validation failed" : message)
        case .invalidResponse(let message):
            return .networkError(message)
        case .decodingFailed(let error):
            return .networkError("Failed to decode response: \(error.localizedDescription)")
        case .unknown(_, let message):
            return .networkError(message ?? "Unknown error")
        }
    }
}
