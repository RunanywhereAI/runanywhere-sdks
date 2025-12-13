//
//  AnalyticsEventData.swift
//  RunAnywhere SDK
//
//  Structured event data models for strongly typed analytics
//

import Foundation

/// Base protocol for all structured event data
public protocol AnalyticsEventData: Codable, Sendable {}

// MARK: - Session Event Data Models

/// Session started event data
public struct SessionStartedData: AnalyticsEventData {
    public let modelId: String
    public let sessionType: String
    public let timestamp: TimeInterval

    public init(modelId: String, sessionType: String) {
        self.modelId = modelId
        self.sessionType = sessionType
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Session ended event data
public struct SessionEndedData: AnalyticsEventData {
    public let sessionId: String
    public let duration: TimeInterval
    public let timestamp: TimeInterval

    public init(sessionId: String, duration: TimeInterval) {
        self.sessionId = sessionId
        self.duration = duration
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Error Event Data Models

/// Generic error event data with full context including stack trace
public struct ErrorEventData: AnalyticsEventData {
    /// The error description
    public let error: String

    /// The context where the error occurred (e.g., "generation", "stt", "tts")
    public let context: String

    /// Machine-readable error code
    public let errorCode: String?

    /// Error category for grouping
    public let category: String?

    /// Stack trace at the point of error (debug builds only)
    public let stackTrace: String?

    /// Source file where error occurred
    public let file: String?

    /// Line number where error occurred
    public let line: Int?

    /// Function name where error occurred
    public let function: String?

    /// Timestamp when the error occurred
    public let timestamp: TimeInterval

    /// Full initializer with all context fields
    public init(
        error: String,
        context: AnalyticsContext,
        errorCode: String? = nil,
        category: String? = nil,
        stackTrace: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        function: String? = nil
    ) {
        self.error = error
        self.context = context.rawValue
        self.errorCode = errorCode
        self.category = category
        self.stackTrace = stackTrace
        self.file = file
        self.line = line
        self.function = function
        self.timestamp = Date().timeIntervalSince1970
    }

    /// Convenience initializer from Error with automatic context capture
    public init(
        from error: Error,
        context: AnalyticsContext,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let raError = error.asRunAnywhereError()
        let errorContext = error.errorContext ?? ErrorContext(file: file, line: line, function: function)

        self.error = raError.errorDescription ?? error.localizedDescription
        self.context = context.rawValue
        self.errorCode = String(raError.code.rawValue)
        self.category = raError.category.rawValue
        self.file = errorContext.file
        self.line = errorContext.line
        self.function = errorContext.function
        self.timestamp = Date().timeIntervalSince1970

        // Only include stack trace in debug builds
        #if DEBUG
        self.stackTrace = errorContext.formattedStackTrace
        #else
        self.stackTrace = nil
        #endif
    }
}
