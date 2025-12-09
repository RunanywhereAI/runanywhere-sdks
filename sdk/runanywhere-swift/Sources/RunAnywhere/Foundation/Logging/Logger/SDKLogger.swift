//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Centralized logging utility for SDK components
//

import Foundation

/// Centralized logging utility for SDK components
public struct SDKLogger {
    private let category: String

    public init(category: String = "SDK") {
        self.category = category
    }

    // MARK: - Standard Logging Methods

    /// Log a debug message
    public func debug(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .debug, category: category, message: message, metadata: metadata)
    }

    /// Log an info message
    public func info(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .info, category: category, message: message, metadata: metadata)
    }

    /// Log a warning message
    public func warning(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .warning, category: category, message: message, metadata: metadata)
    }

    /// Log an error message
    public func error(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    /// Log a fault message
    public func fault(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }

    /// Log a message with a specific level
    public func log(level: LogLevel, _ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: level, category: category, message: message, metadata: metadata)
    }

    // MARK: - Error Logging with Context

    /// Log an error with full context including stack trace, file, line, and function
    /// This automatically captures the call site information and converts to RunAnywhereError
    /// - Parameters:
    ///   - error: The error to log
    ///   - additionalInfo: Optional additional context information
    ///   - file: Automatically captured source file
    ///   - line: Automatically captured line number
    ///   - function: Automatically captured function name
    public func logError(  // swiftlint:disable:this function_body_length
        _ error: Error,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        // Get or create error context with stack trace
        let context = error.errorContext ?? ErrorContext(file: file, line: line, function: function)
        let raError = error.asRunAnywhereError()

        // Build metadata with all error details
        var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "errorCode": raError.code.rawValue,
            "errorCodeMessage": raError.code.message,
            "errorCategory": raError.category.rawValue,
            "sourceFile": context.file,
            "sourceLine": context.line,
            "sourceFunction": context.function,
            "thread": context.threadInfo,
            "errorTimestamp": ISO8601DateFormatter().string(from: context.timestamp)
        ]

        // Add underlying error info if present
        if let underlying = raError.underlyingError {
            metadata["underlyingError"] = underlying.localizedDescription
        }

        // Add additional info if provided
        if let additional = additionalInfo {
            metadata["additionalInfo"] = additional
        }

        // Include stack trace (always in debug, configurable in release)
        #if DEBUG
        metadata["stackTrace"] = context.formattedStackTrace
        #endif

        // Format the error message
        let message = """
        \(raError.errorDescription ?? "Unknown error")
        [Code: \(raError.code.rawValue)] [Category: \(raError.category.rawValue)]
        Location: \(context.locationString)
        """

        // Log at error level
        LoggingManager.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    /// Log an error as a fault (critical error) with full context
    /// Use this for unrecoverable errors that indicate a serious problem
    /// - Parameters:
    ///   - error: The error to log
    ///   - additionalInfo: Optional additional context information
    ///   - file: Automatically captured source file
    ///   - line: Automatically captured line number
    ///   - function: Automatically captured function name
    public func logFault(
        _ error: Error,
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
            "sourceFile": context.file,
            "sourceLine": context.line,
            "sourceFunction": context.function,
            "stackTrace": context.formattedStackTrace // Always include for faults
        ]

        if let additional = additionalInfo {
            metadata["additionalInfo"] = additional
        }

        let message = """
        FAULT: \(raError.errorDescription ?? "Unknown error")
        [Code: \(raError.code.rawValue)] [Category: \(raError.category.rawValue)]
        Location: \(context.locationString)
        Stack Trace:
        \(context.formattedStackTrace)
        """

        LoggingManager.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }
}
