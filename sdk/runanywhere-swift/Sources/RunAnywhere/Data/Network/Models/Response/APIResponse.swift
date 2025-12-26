//
//  APIResponse.swift
//  RunAnywhere SDK
//
//  Generic API response wrapper for type-safe backend communication
//

import Foundation

// MARK: - Generic API Response

/// Generic API response wrapper that handles both success and error cases
/// Matches backend response patterns for type-safe parsing
public struct APIResponse<T: Decodable>: Decodable {
    /// Whether the request was successful
    public let success: Bool

    /// The response data (present on success)
    public let data: T?

    /// Error information (present on failure)
    public let error: APIErrorInfo?

    /// HTTP status code
    public let statusCode: Int

    // MARK: - Convenience Accessors

    /// Returns the data or throws the error
    public func unwrap() throws -> T {
        if let data = data {
            return data
        }
        if let error = error {
            throw error.toSDKError(statusCode: statusCode)
        }
        throw SDKError.network(.unknown, "No data or error in response (status: \(statusCode))")
    }

    /// Check if response indicates success
    public var isSuccess: Bool {
        success && data != nil
    }

    /// Check if response indicates failure
    public var isFailure: Bool {
        !success || error != nil
    }
}

// MARK: - API Error Info

/// Simplified error info from API responses.
/// Captures the raw response for logging while extracting key fields for error construction.
public struct APIErrorInfo: Decodable, Sendable {
    /// The raw JSON response body (for logging/debugging)
    public let rawBody: String?

    /// Primary error message (extracted from detail, message, or error fields)
    public let message: String?

    /// Error code from backend (if provided)
    public let code: String?

    /// HTTP status code
    public let statusCode: Int

    /// The URL that was requested (for context)
    public let requestURL: String?

    // MARK: - Initialization

    /// Create from raw response data
    public init(data: Data?, statusCode: Int, requestURL: String? = nil) {
        self.statusCode = statusCode
        self.requestURL = requestURL

        // Store raw body for logging
        if let data = data {
            self.rawBody = String(data: data, encoding: .utf8)
        } else {
            self.rawBody = nil
        }

        // Try to extract message and code from common response formats
        var extractedMessage: String?
        var extractedCode: String?

        if let data = data {
            // Try decoding as standard error response first
            if let standardError = try? JSONDecoder().decode(StandardErrorResponse.self, from: data) {
                extractedMessage = standardError.detail ?? standardError.message ?? standardError.error
                extractedCode = standardError.code
            }
            // Try extracting from Pydantic validation error format using simple dictionary access
            else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: AnyHashable],
                    let detail = json["detail"] as? [[String: AnyHashable]],
                    let firstError = detail.first,
                    let msg = firstError["msg"] as? String {
                extractedMessage = msg
            }
        }

        self.message = extractedMessage
        self.code = extractedCode
    }

    /// Decode from JSON (for APIResponse parsing)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode common fields
        let detail = try? container.decode(String.self, forKey: .detail)
        let messageField = try? container.decode(String.self, forKey: .message)
        let errorField = try? container.decode(String.self, forKey: .error)

        self.message = detail ?? messageField ?? errorField
        self.code = try? container.decode(String.self, forKey: .code)
        self.rawBody = nil // Not available when decoding from Codable
        self.statusCode = 0 // Set by APIResponse
        self.requestURL = nil
    }

    private enum CodingKeys: String, CodingKey {
        case detail, message, error, code
    }

    // MARK: - Error Conversion

    /// Convert to SDKError with appropriate code based on status
    public func toSDKError(statusCode: Int) -> SDKError {
        let errorMessage = message ?? "HTTP \(statusCode)"

        switch statusCode {
        case 401:
            return SDKError.network(.unauthorized, errorMessage)
        case 403:
            return SDKError.network(.forbidden, errorMessage)
        case 404:
            return SDKError.network(.invalidResponse, errorMessage)
        case 408, 504:
            return SDKError.network(.timeout, errorMessage)
        case 422:
            return SDKError.network(.validationFailed, errorMessage)
        case 400..<500:
            return SDKError.network(.httpError, "Client error \(statusCode): \(errorMessage)")
        case 500..<600:
            return SDKError.network(.serverError, "Server error \(statusCode): \(errorMessage)")
        default:
            return SDKError.network(.unknown, "\(errorMessage) (status: \(statusCode))")
        }
    }

    // MARK: - Debug Description

    /// Full debug description for logging (includes raw body)
    public var debugDescription: String {
        var parts: [String] = ["HTTP \(statusCode)"]
        if let url = requestURL {
            parts.append("URL: \(url)")
        }
        if let message = message {
            parts.append("Message: \(message)")
        }
        if let code = code {
            parts.append("Code: \(code)")
        }
        if let body = rawBody {
            parts.append("Body: \(body)")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Error Response Types

/// Standard error response format from backend
private struct StandardErrorResponse: Decodable {
    let detail: String?
    let message: String?
    let error: String?
    let code: String?
}

// Note: Pydantic validation errors are handled via JSONSerialization for simplicity
// No dedicated struct needed - just extracts detail[0].msg from JSON dictionary
