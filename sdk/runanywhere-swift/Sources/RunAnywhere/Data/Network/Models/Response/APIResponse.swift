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
    public let error: APIErrorResponse?

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

// MARK: - API Error Response (Backend Format)

/// Error response structure matching FastAPI/Pydantic backend format
public struct APIErrorResponse: Decodable, Sendable {
    /// Error detail - can be a string or array of validation errors
    public let detail: APIErrorDetail?

    /// Alternative error message field
    public let message: String?

    /// Alternative error field
    public let error: String?

    /// Error code from backend
    public let code: String?

    /// Convert to SDKError
    public func toSDKError(statusCode: Int) -> SDKError {
        // Extract message from detail, message, or error fields
        var errorMessage: String?
        if let detail = detail {
            switch detail {
            case .message(let msg):
                errorMessage = msg
            case .validationErrors(let errors):
                let messages = errors.map { $0.formattedMessage }
                errorMessage = messages.joined(separator: "; ")
            }
        } else if let message = message {
            errorMessage = message
        } else if let error = error {
            errorMessage = error
        }

        // Map status code to appropriate SDKError
        switch statusCode {
        case 401:
            return SDKError.network(.unauthorized, errorMessage ?? "Authentication required")
        case 403:
            return SDKError.network(.forbidden, errorMessage ?? "Access denied")
        case 404:
            return SDKError.network(.invalidResponse, errorMessage ?? "Resource not found")
        case 408, 504:
            return SDKError.network(.timeout, errorMessage ?? "Request timed out")
        case 422:
            return SDKError.network(.validationFailed, errorMessage ?? "Validation failed")
        case 400..<500:
            return SDKError.network(.httpError, "Client error \(statusCode): \(errorMessage ?? "Unknown error")")
        case 500..<600:
            return SDKError.network(.serverError, "Server error \(statusCode): \(errorMessage ?? "Unknown error")")
        default:
            return SDKError.network(.unknown, errorMessage ?? "Unknown error with status code \(statusCode)")
        }
    }
}

// MARK: - Error Detail (Supports String or Validation Array)

/// Error detail that can be either a simple string or Pydantic validation errors
public enum APIErrorDetail: Decodable, Sendable {
    case message(String)
    case validationErrors([ValidationError])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try parsing as string first
        if let message = try? container.decode(String.self) {
            self = .message(message)
            return
        }

        // Try parsing as validation error array
        if let errors = try? container.decode([ValidationError].self) {
            self = .validationErrors(errors)
            return
        }

        throw DecodingError.typeMismatch(
            APIErrorDetail.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected String or [ValidationError]"
            )
        )
    }
}

// MARK: - Pydantic Validation Error

/// Pydantic validation error structure
public struct ValidationError: Decodable, Sendable {
    /// Error message
    public let msg: String

    /// Location path (e.g., ["body", "events", 0, "id"])
    public let loc: [LocationElement]

    /// Error type (e.g., "value_error", "type_error")
    public let type: String

    /// Optional input that caused the error
    public let input: AnyCodable?

    /// Optional URL for more information
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case msg, loc, type, input, url
    }

    /// Format the field path from location array
    public var fieldPath: String {
        loc.dropFirst() // Skip "body"
            .map { element -> String in
                switch element {
                case .string(let str): return str
                case .int(let idx): return "[\(idx)]"
                }
            }
            .joined(separator: ".")
            .replacingOccurrences(of: ".\\[", with: "[", options: .regularExpression)
    }

    /// Format as human-readable string
    public var formattedMessage: String {
        let path = fieldPath
        return path.isEmpty ? msg : "\(path): \(msg)"
    }
}

// MARK: - Location Element (String or Int)

/// Location element that can be either a string (field name) or int (array index)
public enum LocationElement: Decodable, Sendable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                LocationElement.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or Int"
                )
            )
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic values
public struct AnyCodable: Decodable, Sendable {
    public let value: any Sendable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = "unknown"
        }
    }
}
