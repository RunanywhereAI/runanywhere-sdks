//
//  SensitiveDataPolicy.swift
//  RunAnywhere SDK
//
//  Defines policies for handling sensitive data in logs
//

import Foundation

/// Policy for handling sensitive data in logs
public enum SensitiveDataPolicy {
    /// Data is not sensitive - can be logged locally and remotely
    case none

    /// Data contains sensitive information - log locally only in debug mode, never remotely
    case sensitive

    /// Data is critical - never log the actual content, only log category/type
    case critical

    /// Completely redact - don't log at all
    case redacted
}

/// Categories of sensitive data for classification
public enum SensitiveDataCategory {
    // Authentication & Credentials
    case apiKey
    case bearerToken
    case password
    case credential

    // User Content
    case userPrompt
    case generatedResponse
    case conversationHistory
    case systemPrompt
    case userMessage

    // Personal Information
    case userId
    case email
    case phoneNumber
    case deviceIdentifier

    // Configuration & System
    case modelPath
    case fileSystemPath
    case internalURL
    case errorDetails

    // Business Logic
    case costCalculation
    case routingDecision
    case performanceMetric

    var defaultPolicy: SensitiveDataPolicy {
        switch self {
        case .apiKey, .bearerToken, .password, .credential:
            return .redacted
        case .userPrompt, .generatedResponse, .conversationHistory, .systemPrompt, .userMessage:
            return .critical
        case .userId, .email, .phoneNumber, .deviceIdentifier:
            return .critical
        case .modelPath, .fileSystemPath, .internalURL:
            return .sensitive
        case .errorDetails, .costCalculation, .routingDecision, .performanceMetric:
            return .sensitive
        }
    }

    var sanitizedPlaceholder: String {
        switch self {
        case .apiKey: return "[API_KEY]"
        case .bearerToken: return "[TOKEN]"
        case .password: return "[PASSWORD]"
        case .credential: return "[CREDENTIAL]"
        case .userPrompt: return "[USER_PROMPT]"
        case .generatedResponse: return "[GENERATED_RESPONSE]"
        case .conversationHistory: return "[CONVERSATION]"
        case .systemPrompt: return "[SYSTEM_PROMPT]"
        case .userMessage: return "[USER_MESSAGE]"
        case .userId: return "[USER_ID]"
        case .email: return "[EMAIL]"
        case .phoneNumber: return "[PHONE]"
        case .deviceIdentifier: return "[DEVICE_ID]"
        case .modelPath: return "[MODEL_PATH]"
        case .fileSystemPath: return "[FILE_PATH]"
        case .internalURL: return "[URL]"
        case .errorDetails: return "[ERROR_DETAILS]"
        case .costCalculation: return "[COST_DATA]"
        case .routingDecision: return "[ROUTING_DATA]"
        case .performanceMetric: return "[PERFORMANCE_DATA]"
        }
    }
}

/// Metadata key for marking sensitive data
public struct LogMetadataKeys {
    public static let sensitiveDataPolicy = "__sensitive_data_policy"
    public static let sensitiveDataCategory = "__sensitive_data_category"
    public static let isUserContent = "__is_user_content"
    public static let containsPII = "__contains_pii"
    public static let sanitized = "__sanitized"
}
