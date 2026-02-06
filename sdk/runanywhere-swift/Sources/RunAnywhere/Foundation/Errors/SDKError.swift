//
//  SDKError.swift
//  RunAnywhere
//
//  Created by RunAnywhere on 2024.
//

import Foundation

/// The unified error type for the RunAnywhere SDK.
///
/// All errors in the SDK are represented by this type, providing consistent
/// error handling across all components and features.
///
/// Errors are automatically logged to configured destinations (Sentry, console)
/// when created via factory methods.
///
/// Example usage:
/// ```swift
/// throw SDKError.stt(.modelNotFound, "Whisper model not found at path")
/// throw SDKError.network(.timeout, "Request timed out after 30 seconds")
/// ```
public struct SDKError: Error, LocalizedError, Sendable, CustomStringConvertible {

    // MARK: - Properties

    /// The specific error code identifying what went wrong
    public let code: ErrorCode

    /// Human-readable message with context about the error
    public let message: String

    /// The component/modality category this error belongs to
    public let category: ErrorCategory

    /// Stack trace captured at the time of error creation
    public let stackTrace: [String]

    /// The underlying error that caused this error, if any
    public let underlyingError: (any Error)?

    // MARK: - Initialization

    /// Creates a new SDKError with all properties.
    ///
    /// Prefer using the factory methods (e.g., `SDKError.stt()`, `SDKError.llm()`)
    /// which automatically capture the stack trace and log the error.
    public init(
        code: ErrorCode,
        message: String,
        category: ErrorCategory,
        stackTrace: [String],
        underlyingError: (any Error)? = nil
    ) {
        self.code = code
        self.message = message
        self.category = category
        self.stackTrace = stackTrace
        self.underlyingError = underlyingError
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        message
    }

    public var failureReason: String? {
        "[\(category.rawValue.uppercased())] \(code.rawValue)"
    }

    public var recoverySuggestion: String? {
        switch code {
        case .notInitialized:
            return "Initialize the component before using it."
        case .modelNotFound:
            return "Ensure the model is downloaded and the path is correct."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .insufficientStorage:
            return "Free up storage space and try again."
        case .insufficientMemory:
            return "Close other applications to free up memory."
        case .microphonePermissionDenied:
            return "Grant microphone permission in Settings."
        case .timeout:
            return "Try again or check your connection."
        case .invalidAPIKey:
            return "Verify your API key is correct."
        case .cancelled:
            return nil
        default:
            return nil
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var result = "SDKError[\(category.rawValue).\(code.rawValue)]: \(message)"
        if let underlying = underlyingError {
            result += "\n  Caused by: \(underlying)"
        }
        return result
    }

    // MARK: - Debug Helpers

    /// Returns a detailed debug description including stack trace
    public var debugDescription: String {
        var result = description
        if !stackTrace.isEmpty {
            result += "\n  Stack trace:\n"
            for frame in stackTrace.prefix(10) {
                result += "    \(frame)\n"
            }
            if stackTrace.count > 10 {
                result += "    ... and \(stackTrace.count - 10) more frames\n"
            }
        }
        return result
    }

    /// Returns a condensed stack trace with only SDK frames
    public var sdkStackTrace: [String] {
        stackTrace.filter { $0.contains("RunAnywhere") }
    }
}

// MARK: - Factory Methods

extension SDKError {

    /// Creates an SDKError with automatic stack trace capture and logging.
    ///
    /// - Parameters:
    ///   - code: The error code
    ///   - message: Human-readable error message
    ///   - category: The error category
    ///   - underlyingError: Optional underlying error
    ///   - shouldLog: Whether to automatically log this error (default: true)
    /// - Returns: A new SDKError instance
    public static func make(
        code: ErrorCode,
        message: String,
        category: ErrorCategory,
        underlyingError: (any Error)? = nil,
        shouldLog: Bool = true
    ) -> SDKError {
        let error = SDKError(
            code: code,
            message: message,
            category: category,
            stackTrace: Thread.callStackSymbols,
            underlyingError: underlyingError
        )

        // Automatically log the error unless it's expected (cancelled, etc.)
        if shouldLog && !code.isExpected {
            error.log()
        }

        return error
    }

    // MARK: - Category-Specific Factories

    /// Creates a general SDK error.
    public static func general(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .general, underlyingError: underlying)
    }

    /// Creates a Speech-to-Text error.
    public static func stt(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .stt, underlyingError: underlying)
    }

    /// Creates a Text-to-Speech error.
    public static func tts(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .tts, underlyingError: underlying)
    }

    /// Creates an LLM error.
    public static func llm(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .llm, underlyingError: underlying)
    }

    /// Creates a Memory/RAG error.
    public static func memory(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .memory, underlyingError: underlying)
    }

    /// Creates a VAD error.
    public static func vad(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .vad, underlyingError: underlying)
    }

    /// Creates a VLM error.
    public static func vlm(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .vlm, underlyingError: underlying)
    }

    /// Creates a Speaker Diarization error.
    public static func speakerDiarization(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .speakerDiarization, underlyingError: underlying)
    }

    /// Creates a Wake Word error.
    public static func wakeWord(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .wakeWord, underlyingError: underlying)
    }

    /// Creates a Voice Agent error.
    public static func voiceAgent(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .voiceAgent, underlyingError: underlying)
    }

    /// Creates a download error.
    public static func download(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .download, underlyingError: underlying)
    }

    /// Creates a file management error.
    public static func fileManagement(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .fileManagement, underlyingError: underlying)
    }

    /// Creates a network error.
    public static func network(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .network, underlyingError: underlying)
    }

    /// Creates an authentication error.
    public static func authentication(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .authentication, underlyingError: underlying)
    }

    /// Creates a security error.
    public static func security(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .security, underlyingError: underlying)
    }

    /// Creates a runtime error.
    public static func runtime(
        _ code: ErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKError {
        make(code: code, message: message, category: .runtime, underlyingError: underlying)
    }
}

// MARK: - Error Logging

extension SDKError {

    /// Log this error to all configured destinations.
    ///
    /// Called automatically by factory methods for unexpected errors.
    /// Can be called manually for errors created via init.
    public func log(file: String = #file, line: Int = #line, function: String = #function) {
        let level: LogLevel = (code == .cancelled) ? .info : .error
        let fileName = (file as NSString).lastPathComponent

        var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "error_code": code.rawValue,
            "error_category": category.rawValue,
            "source_file": fileName,
            "source_line": line,
            "source_function": function
        ]

        if let underlying = underlyingError {
            metadata["underlying_error"] = String(describing: underlying)
        }

        if let reason = failureReason {
            metadata["failure_reason"] = reason
        }

        // Include condensed SDK stack trace
        let sdkFrames = sdkStackTrace.prefix(5)
        if !sdkFrames.isEmpty {
            metadata["stack_trace"] = sdkFrames.joined(separator: "\n")
        }

        Logging.shared.log(
            level: level,
            category: category.rawValue,
            message: message,
            metadata: metadata
        )
    }
}

// MARK: - Error Conversion

extension SDKError {

    /// Converts any Error to an SDKError.
    ///
    /// If the error is already an SDKError, returns it as-is.
    /// Otherwise, wraps it as an unknown general error.
    public static func from(_ error: any Error, category: ErrorCategory = .general) -> SDKError {
        if let sdkError = error as? SDKError {
            return sdkError
        }

        let nsError = error as NSError

        // Handle common system errors
        if nsError.domain == NSURLErrorDomain {
            return fromURLError(nsError, category: category)
        }

        return make(
            code: .unknown,
            message: error.localizedDescription,
            category: category,
            underlyingError: error
        )
    }

    /// Converts an optional Error to an SDKError.
    ///
    /// If the error is nil, returns a generic "Unknown error" SDKError.
    /// Otherwise, delegates to `from(_:category:)`.
    public static func from(_ error: (any Error)?, category: ErrorCategory = .general) -> SDKError {
        guard let error = error else {
            return make(
                code: .unknown,
                message: "Unknown error",
                category: category,
                underlyingError: nil
            )
        }
        return from(error, category: category)
    }

    private static func fromURLError(_ nsError: NSError, category: ErrorCategory) -> SDKError {
        let code: ErrorCode
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            code = .networkUnavailable
        case NSURLErrorTimedOut:
            code = .timeout
        case NSURLErrorCancelled:
            code = .cancelled
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            code = .networkError
        default:
            code = .networkError
        }

        return make(
            code: code,
            message: nsError.localizedDescription,
            category: category,
            underlyingError: nsError
        )
    }
}

// MARK: - Equatable

extension SDKError: Equatable {
    public static func == (lhs: SDKError, rhs: SDKError) -> Bool {
        lhs.code == rhs.code &&
        lhs.category == rhs.category &&
        lhs.message == rhs.message
    }
}

// MARK: - Hashable

extension SDKError: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(category)
        hasher.combine(message)
    }
}

// MARK: - Telemetry Properties

extension SDKError {

    /// Lightweight properties for telemetry/analytics events.
    ///
    /// Use this for event serialization sent to the backend analytics service.
    /// Only includes essential fields needed for metrics and dashboards.
    ///
    /// For full error details (stack traces, underlying errors), use `SDKLogger`
    /// which routes to console and Sentry for debugging and error monitoring.
    public var telemetryProperties: [String: String] {
        [
            "error_code": code.rawValue,
            "error_category": category.rawValue,
            "error_message": message
        ]
    }
}

// MARK: - ONNX Runtime Error Conversion

extension SDKError {

    /// Convert ONNX Runtime C error code to SDKError
    public static func fromONNXCode(_ code: Int32) -> SDKError {
        switch code {
        case 0:
            return runtime(.unknown, "Unexpected success code passed to error handler")
        case -1:
            return runtime(.initializationFailed, "ONNX Runtime initialization failed")
        case -2:
            return runtime(.modelLoadFailed, "Failed to load ONNX model")
        case -3:
            return runtime(.generationFailed, "ONNX inference failed")
        case -4:
            return runtime(.invalidState, "Invalid ONNX handle")
        case -5:
            return runtime(.invalidInput, "Invalid ONNX parameters")
        case -6:
            return runtime(.insufficientMemory, "ONNX Runtime out of memory")
        case -7:
            return runtime(.notImplemented, "ONNX feature not implemented")
        case -8:
            return runtime(.cancelled, "ONNX operation cancelled")
        case -9:
            return runtime(.timeout, "ONNX operation timed out")
        case -10:
            return runtime(.storageError, "ONNX IO error")
        default:
            return runtime(.unknown, "ONNX error code: \(code)")
        }
    }
}
