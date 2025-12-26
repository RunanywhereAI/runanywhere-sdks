//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Production-ready logging utility with full stack trace capture.
//  Thread-safe, Sendable-compliant, and optimized for debugging.
//

import Foundation

// MARK: - SDKLogger

/// Production-ready logging utility for SDK components.
///
/// Features:
/// - **Thread-safe**: Sendable-compliant for concurrent use
/// - **Stack traces**: Full call stack capture for debugging
/// - **Structured metadata**: Key-value pairs for log aggregation
/// - **Category support**: Filter logs by component
///
/// ## Usage
/// ```swift
/// let logger = SDKLogger(category: "LLM")
/// logger.info("Model loaded successfully")
/// logger.logError(error, additionalInfo: "During generation")
/// ```
public struct SDKLogger: Sendable {
    /// The category/component name for this logger instance.
    public let category: String

    /// Creates a logger for the specified category.
    /// - Parameter category: The component or module name (e.g., "LLM", "STT", "Download")
    public init(category: String = "SDK") {
        self.category = category
    }

    // MARK: - Standard Logging

    /// Log a debug message (verbose development info).
    @inlinable
    public func debug(_ message: @autoclosure () -> String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        #if DEBUG
        Logging.shared.log(level: .debug, category: category, message: message(), metadata: metadata)
        #endif
    }

    /// Log an informational message.
    public func info(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .info, category: category, message: message, metadata: metadata)
    }

    /// Log a warning message (potential issue, not an error).
    public func warning(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .warning, category: category, message: message, metadata: metadata)
    }

    /// Log an error message.
    public func error(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    /// Log a fault message (critical/unrecoverable error).
    public func fault(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }

    /// Log with a specific level.
    public func log(level: LogLevel, _ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: level, category: category, message: message, metadata: metadata)
    }

    // MARK: - Error Logging with Stack Trace

    /// Log an error with full debugging context.
    ///
    /// Captures:
    /// - Error description and recovery suggestion
    /// - Source location (file, line, function)
    /// - Thread information
    /// - Full stack trace (filtered for relevance)
    /// - Timestamp
    ///
    /// - Parameters:
    ///   - error: The error to log
    ///   - additionalInfo: Optional context about what operation was being performed
    ///   - file: Auto-captured source file
    ///   - line: Auto-captured line number
    ///   - function: Auto-captured function name
    public func logError(
        _ error: Error,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let context = ErrorLogContext(
            error: error,
            file: file,
            line: line,
            function: function,
            additionalInfo: additionalInfo
        )

        Logging.shared.log(
            level: .error,
            category: category,
            message: context.formattedMessage,
            metadata: context.metadata
        )
    }

    /// Log a critical/unrecoverable error with full stack trace.
    ///
    /// Use for errors that indicate a serious SDK bug or unrecoverable state.
    /// Always includes full stack trace regardless of build configuration.
    ///
    /// - Parameters:
    ///   - error: The error to log
    ///   - additionalInfo: Optional context about what operation was being performed
    ///   - file: Auto-captured source file
    ///   - line: Auto-captured line number
    ///   - function: Auto-captured function name
    public func logFault(
        _ error: Error,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let context = ErrorLogContext(
            error: error,
            file: file,
            line: line,
            function: function,
            additionalInfo: additionalInfo,
            isFault: true
        )

        Logging.shared.log(
            level: .fault,
            category: category,
            message: context.formattedMessage,
            metadata: context.metadata
        )
    }
}

// MARK: - ErrorLogContext

/// Internal helper for building error log context.
/// Captures all debugging information at the call site.
private struct ErrorLogContext {
    let raError: RunAnywhereError
    let fileName: String
    let line: Int
    let function: String
    let additionalInfo: String?
    let threadInfo: String
    let timestamp: String
    let stackTrace: String
    let isFault: Bool

    init(
        error: Error,
        file: String,
        line: Int,
        function: String,
        additionalInfo: String?,
        isFault: Bool = false
    ) {
        self.raError = error.asRunAnywhereError()
        self.fileName = (file as NSString).lastPathComponent
        self.line = line
        self.function = function
        self.additionalInfo = additionalInfo
        self.threadInfo = Self.captureThreadInfo()
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.stackTrace = Self.captureStackTrace()
        self.isFault = isFault
    }

    /// Formatted message for logging.
    var formattedMessage: String {
        let prefix = isFault ? "FAULT: " : ""
        var message = """
        \(prefix)\(raError.errorDescription ?? "Unknown error")
        └─ Location: \(fileName):\(line) in \(function)
        └─ Thread: \(threadInfo)
        └─ Code: \(raError.errorCode)
        """

        if let additional = additionalInfo {
            message += "\n└─ Context: \(additional)"
        }

        if let reason = raError.failureReason {
            message += "\n└─ Reason: \(reason)"
        }

        if let suggestion = raError.recoverySuggestion {
            message += "\n└─ Recovery: \(suggestion)"
        }

        message += "\n└─ Stack Trace:\n\(stackTrace)"

        return message
    }

    /// Structured metadata for log aggregation systems.
    var metadata: [String: Any] { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        var meta: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "error_code": raError.errorCode,
            "error_domain": runAnywhereErrorDomain,
            "source_file": fileName,
            "source_line": line,
            "source_function": function,
            "thread": threadInfo,
            "timestamp": timestamp,
            "stack_trace": stackTrace
        ]

        if let additional = additionalInfo {
            meta["context"] = additional
        }

        if let reason = raError.failureReason {
            meta["failure_reason"] = reason
        }

        if isFault {
            meta["severity"] = "fault"
        }

        return meta
    }

    // MARK: - Stack Trace Capture

    /// Capture the current call stack, filtered for relevance.
    private static func captureStackTrace() -> String {
        let symbols = Thread.callStackSymbols

        // Filter to relevant frames
        let relevantFrames = symbols
            .enumerated()
            .filter { index, frame in
                // Skip logging infrastructure (first 4-5 frames)
                guard index > 4 else { return false }

                // Always include RunAnywhere and App frames
                if frame.contains("RunAnywhere") || frame.contains("App") {
                    return true
                }

                // Exclude noisy system frames
                let excludePatterns = [
                    "libswiftCore",
                    "libdispatch",
                    "CoreFoundation",
                    "libsystem",
                    "UIKitCore",
                    "SwiftUI",
                    "AttributeGraph"
                ]

                return !excludePatterns.contains { frame.contains($0) }
            }
            .prefix(25)
            .map { index, frame in
                // Clean up the frame for readability
                let cleaned = Self.cleanStackFrame(frame)
                return "   \(index). \(cleaned)"
            }

        if relevantFrames.isEmpty {
            // Fallback: show raw frames
            return symbols
                .prefix(20)
                .enumerated()
                .map { "   \($0.offset). \($0.element)" }
                .joined(separator: "\n")
        }

        return relevantFrames.joined(separator: "\n")
    }

    /// Clean up a stack frame for readability.
    private static func cleanStackFrame(_ frame: String) -> String {
        // Stack frames look like:
        // "4   RunAnywhere  0x000000010a1b2c3d $s11RunAnywhere..."
        // We want to preserve the important parts but make it readable
        frame
    }

    /// Capture current thread information.
    private static func captureThreadInfo() -> String {
        if Thread.isMainThread {
            return "main"
        }

        if let name = Thread.current.name, !name.isEmpty {
            return name
        }

        // For unnamed background threads, include useful identifiers
        if let queueLabel = OperationQueue.current?.underlyingQueue?.label, !queueLabel.isEmpty {
            return queueLabel
        }

        return "background-\(Unmanaged.passUnretained(Thread.current).toOpaque())"
    }
}

// MARK: - Convenience Loggers

extension SDKLogger {
    /// Shared logger for general SDK operations.
    public static let shared = SDKLogger(category: "RunAnywhere")

    /// Logger for LLM operations.
    public static let llm = SDKLogger(category: "LLM")

    /// Logger for STT operations.
    public static let stt = SDKLogger(category: "STT")

    /// Logger for TTS operations.
    public static let tts = SDKLogger(category: "TTS")

    /// Logger for download operations.
    public static let download = SDKLogger(category: "Download")

    /// Logger for model management.
    public static let models = SDKLogger(category: "Models")
}
