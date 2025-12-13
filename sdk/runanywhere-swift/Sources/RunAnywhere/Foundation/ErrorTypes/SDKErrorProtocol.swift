//
//  SDKErrorProtocol.swift
//  RunAnywhere SDK
//
//  Base protocol for all SDK errors providing consistent error handling
//

import Foundation

/// Base protocol that all SDK error types should conform to
/// Provides consistent error handling, categorization, and analytics integration
public protocol SDKErrorProtocol: LocalizedError, Sendable {
    /// The error code for machine-readable identification
    var code: ErrorCode { get }

    /// The category of this error for grouping/filtering
    var category: ErrorCategory { get }

    /// The underlying error that caused this error, if any
    var underlyingError: Error? { get }
}

// MARK: - Default Implementations

extension SDKErrorProtocol {
    /// Default implementation returns nil for underlying error
    public var underlyingError: Error? { nil }

    /// Convert this error to analytics event data with optional context
    public func toAnalyticsData(context: AnalyticsContext, errorContext: ErrorContext? = nil) -> LegacyErrorEventData {
        LegacyErrorEventData(
            error: errorDescription ?? "Unknown error",
            context: context,
            errorCode: String(code.rawValue)
        )
    }
}

// MARK: - Error Conversion Helper

extension Error {
    /// Convert any error to RunAnywhereError for consistent public API
    public func asRunAnywhereError() -> RunAnywhereError {
        if let raError = self as? RunAnywhereError {
            return raError
        }

        // Unwrap ContextualError if present
        if let contextual = self as? ContextualError,
           let raError = contextual.error as? RunAnywhereError {
            return raError
        }

        // Map known error types
        let description = localizedDescription

        // Try to categorize based on error type or message
        if description.lowercased().contains("network") || self is URLError {
            return .networkUnavailable
        } else if description.lowercased().contains("storage") || description.lowercased().contains("disk") {
            return .storageFull
        }

        // Default to generic error
        return .requestFailed(self)
    }

    /// Convert to RunAnywhereError and attach context
    /// - Parameters:
    ///   - file: Automatically captured file
    ///   - line: Automatically captured line
    ///   - function: Automatically captured function
    /// - Returns: Tuple of RunAnywhereError and its context
    public func asRunAnywhereErrorWithContext(
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) -> (error: RunAnywhereError, context: ErrorContext) {
        let context = ErrorContext(file: file, line: line, function: function)
        return (asRunAnywhereError(), context)
    }
}

// MARK: - Error Logging Helpers

/// Log an error with full context including stack trace
/// - Parameters:
///   - error: The error to log
///   - logger: The SDKLogger to use
///   - additionalInfo: Additional context information
///   - file: Automatically captured file
///   - line: Automatically captured line
///   - function: Automatically captured function
public func logError(
    _ error: Error,
    logger: SDKLogger,
    additionalInfo: String? = nil,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
    let context = error.errorContext ?? ErrorContext(file: file, line: line, function: function)
    let raError = error.asRunAnywhereError()

    var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
        "errorCode": raError.code.rawValue,
        "errorCategory": raError.category.rawValue,
        "file": context.file,
        "line": context.line,
        "function": context.function,
        "thread": context.threadInfo
    ]

    if let additional = additionalInfo {
        metadata["additionalInfo"] = additional
    }

    // Include stack trace in debug builds
    #if DEBUG
    metadata["stackTrace"] = context.formattedStackTrace
    #endif

    let message = """
    Error: \(raError.errorDescription ?? "Unknown error")
    Code: \(raError.code.rawValue) (\(raError.code.message))
    Category: \(raError.category.rawValue)
    Location: \(context.locationString)
    """

    logger.error(message, metadata: metadata)
}

/// Throw an error with captured context
/// Usage: throw captureAndThrow(RunAnywhereError.notInitialized)
/// - Parameters:
///   - error: The error to throw
///   - file: Automatically captured file
///   - line: Automatically captured line
///   - function: Automatically captured function
/// - Returns: ContextualError wrapping the error with stack trace
public func captureAndThrow(
    _ error: Error,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) -> ContextualError {
    ContextualError(error, file: file, line: line, function: function)
}
