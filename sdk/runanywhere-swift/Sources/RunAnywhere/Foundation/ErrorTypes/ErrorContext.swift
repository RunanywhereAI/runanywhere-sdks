//
//  ErrorContext.swift
//  RunAnywhere SDK
//
//  Captures error context including stack trace, file, line, and function information
//

import Foundation

/// Context information captured when an error occurs
/// Includes stack trace, source location, and timing information
public struct ErrorContext: Sendable, Codable {
    /// The stack trace at the point of error capture
    public let stackTrace: [String]

    /// The file where the error was captured
    public let file: String

    /// The line number where the error was captured
    public let line: Int

    /// The function where the error was captured
    public let function: String

    /// Timestamp when the error was captured
    public let timestamp: Date

    /// Thread name/ID where the error occurred
    public let threadInfo: String

    /// Initialize with automatic capture of current context
    /// - Parameters:
    ///   - file: The file path (automatically captured via #file)
    ///   - line: The line number (automatically captured via #line)
    ///   - function: The function name (automatically captured via #function)
    public init(
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        self.stackTrace = Thread.callStackSymbols
        self.file = (file as NSString).lastPathComponent
        self.line = line
        self.function = function
        self.timestamp = Date()

        // Capture thread info
        if Thread.isMainThread {
            self.threadInfo = "main"
        } else {
            self.threadInfo = Thread.current.name ?? "background-\(Thread.current.hash)"
        }
    }

    /// Initialize with explicit values (for testing or deserialization)
    public init(
        stackTrace: [String],
        file: String,
        line: Int,
        function: String,
        timestamp: Date,
        threadInfo: String
    ) {
        self.stackTrace = stackTrace
        self.file = file
        self.line = line
        self.function = function
        self.timestamp = timestamp
        self.threadInfo = threadInfo
    }

    /// A formatted string representation of the stack trace
    public var formattedStackTrace: String {
        // Filter out system frames and format nicely
        let relevantFrames = stackTrace
            .enumerated()
            .filter { index, frame in
                // Skip first few frames (error capture infrastructure)
                index > 2 &&
                // Keep frames that might be relevant
                (frame.contains("RunAnywhere") ||
                 frame.contains("App") ||
                 !frame.contains("libswiftCore") &&
                 !frame.contains("libdispatch"))
            }
            .prefix(15) // Limit to 15 frames for readability
            .map { "  \($0.offset). \($0.element)" }

        if relevantFrames.isEmpty {
            return stackTrace.prefix(10).enumerated().map { "  \($0.offset). \($0.element)" }.joined(separator: "\n")
        }

        return relevantFrames.joined(separator: "\n")
    }

    /// A compact single-line location string
    public var locationString: String {
        "\(file):\(line) in \(function)"
    }

    /// Full formatted context for logging
    public var formattedContext: String {
        """
        Location: \(locationString)
        Thread: \(threadInfo)
        Time: \(ISO8601DateFormatter().string(from: timestamp))
        Stack Trace:
        \(formattedStackTrace)
        """
    }
}

// MARK: - Error Context Capture Helper

/// Global function to capture error context at the call site
/// Use this when throwing errors to capture the stack trace
/// - Parameters:
///   - file: Automatically captured file
///   - line: Automatically captured line
///   - function: Automatically captured function
/// - Returns: ErrorContext with current stack trace
public func captureErrorContext(
    file: String = #file,
    line: Int = #line,
    function: String = #function
) -> ErrorContext {
    ErrorContext(file: file, line: line, function: function)
}

// MARK: - Error with Context Wrapper

/// A wrapper that attaches context to any error
public struct ContextualError: Error, LocalizedError, @unchecked Sendable {
    /// The underlying error
    public let error: Error

    /// The captured context
    public let context: ErrorContext

    /// Initialize with an error and automatically capture context
    public init(
        _ error: Error,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        self.error = error
        self.context = ErrorContext(file: file, line: line, function: function)
    }

    /// Initialize with an error and explicit context
    public init(_ error: Error, context: ErrorContext) {
        self.error = error
        self.context = context
    }

    public var errorDescription: String? {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    public var failureReason: String? {
        (error as? LocalizedError)?.failureReason
    }

    public var recoverySuggestion: String? {
        (error as? LocalizedError)?.recoverySuggestion
    }
}

// MARK: - Error Extension for Context

extension Error {
    /// Wrap this error with context information
    /// - Parameters:
    ///   - file: Automatically captured file
    ///   - line: Automatically captured line
    ///   - function: Automatically captured function
    /// - Returns: ContextualError wrapping this error with stack trace
    public func withContext(
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) -> ContextualError {
        ContextualError(self, file: file, line: line, function: function)
    }

    /// Extract context if this is a ContextualError
    public var errorContext: ErrorContext? {
        (self as? ContextualError)?.context
    }

    /// Get the underlying error if wrapped
    public var underlyingErrorValue: Error {
        (self as? ContextualError)?.error ?? self
    }
}
