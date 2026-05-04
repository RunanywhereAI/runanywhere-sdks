//
//  SDKException.swift
//  RunAnywhere
//
//  Wave 2: Canonical Swift error type. Wraps the generated proto `RASDKError`
//  (Sources/RunAnywhere/Generated/errors.pb.swift) so Swift `throws` works
//  while keeping the wire-canonical proto as the source of truth.
//
//  Replaces the legacy `SDKError` struct, `ErrorCode` String enum, and
//  `ErrorCategory` String enum. There is NO `typealias SDKError = SDKException`.
//  Every reference to the legacy types has been rewritten to use this one.
//
//  Usage:
//      throw SDKException.modelNotFound("whisper-base")
//      throw SDKException.stt(.notInitialized, "STT model not loaded")
//      do { ... } catch let ex as SDKException { print(ex.proto.message) }
//

import Foundation

// MARK: - SDKException

/// Canonical Swift-throwable error wrapping the generated proto `RASDKError`.
public struct SDKException: Error, LocalizedError, Sendable, CustomStringConvertible {

    /// The canonical proto-encoded error this exception wraps.
    public let proto: RASDKError

    /// Optional underlying Swift error (not part of the wire proto).
    public let underlying: (any Error)?

    /// Stack trace captured at construction time (debug aid; not on the wire).
    public let stackTrace: [String]

    public init(proto: RASDKError, underlying: (any Error)? = nil) {
        self.proto = proto
        self.underlying = underlying
        self.stackTrace = Thread.callStackSymbols
    }

    public init(
        code: RAErrorCode,
        message: String,
        category: RAErrorCategory = .component,
        underlying: (any Error)? = nil
    ) {
        var p = RASDKError()
        p.code = code
        p.message = message
        p.category = category
        // Round-trip C ABI code: positive proto code ↔ negative rac_result_t
        let raw = code.rawValue
        if raw > 0 && raw <= 899 {
            p.cAbiCode = -Int32(raw)
        }
        if let u = underlying {
            p.nestedMessage = String(describing: u)
        }
        self.proto = p
        self.underlying = underlying
        self.stackTrace = Thread.callStackSymbols
    }

    // MARK: Convenience accessors

    public var code: RAErrorCode { proto.code }
    public var category: RAErrorCategory { proto.category }
    public var message: String { proto.message }

    // MARK: LocalizedError

    public var errorDescription: String? { proto.message }

    public var failureReason: String? {
        "[\(proto.category)] \(proto.code)"
    }

    public var recoverySuggestion: String? {
        switch proto.code {
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
        case .invalidApiKey:
            return "Verify your API key is correct."
        case .cancelled:
            return nil
        default:
            return nil
        }
    }

    // MARK: CustomStringConvertible

    public var description: String {
        var result = "SDKException[\(proto.category).\(proto.code)]: \(proto.message)"
        if let u = underlying {
            result += "\n  Caused by: \(u)"
        }
        return result
    }

    /// Telemetry-only properties (lightweight, safe to ship).
    public var telemetryProperties: [String: String] {
        [
            "error_code": "\(proto.code)",
            "error_category": "\(proto.category)",
            "error_message": proto.message
        ]
    }
}

// MARK: - Equatable / Hashable

extension SDKException: Equatable {
    public static func == (lhs: SDKException, rhs: SDKException) -> Bool {
        lhs.proto.code == rhs.proto.code &&
        lhs.proto.category == rhs.proto.category &&
        lhs.proto.message == rhs.proto.message
    }
}

extension SDKException: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(proto.code.rawValue)
        hasher.combine(proto.category.rawValue)
        hasher.combine(proto.message)
    }
}

// MARK: - Generic factory

extension SDKException {
    /// Generic factory; auto-logs unexpected errors.
    public static func make(
        code: RAErrorCode,
        message: String,
        category: RAErrorCategory = .component,
        underlying: (any Error)? = nil,
        shouldLog: Bool = true
    ) -> SDKException {
        let ex = SDKException(code: code, message: message, category: category, underlying: underlying)
        if shouldLog && !code.isExpected {
            ex.log()
        }
        return ex
    }
}

// MARK: - Category-specific factories
//
// These mirror the legacy SDKError surface so callers like
// `SDKException.stt(.notInitialized, "msg")` continue to read naturally.
// Internally each one routes to `make(code:message:category:...)` with the
// proto's 9-bucket category enum.

extension SDKException {

    /// Generic / general SDK error.
    public static func general(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .internal, underlying: underlying)
    }

    /// Speech-to-Text component error.
    public static func stt(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Text-to-Speech component error.
    public static func tts(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// LLM component error.
    public static func llm(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// VAD component error.
    public static func vad(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// VLM component error.
    public static func vlm(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Speaker diarization component error.
    public static func speakerDiarization(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Wake-word component error.
    public static func wakeWord(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Voice agent component error.
    public static func voiceAgent(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// RAG component error.
    public static func rag(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Diffusion component error.
    public static func diffusion(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .component, underlying: underlying)
    }

    /// Download / model-management error.
    public static func download(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .network, underlying: underlying)
    }

    /// File management error.
    public static func fileManagement(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .io, underlying: underlying)
    }

    /// Network error.
    public static func network(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .network, underlying: underlying)
    }

    /// Authentication error.
    public static func authentication(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .auth, underlying: underlying)
    }

    /// Security error.
    public static func security(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .auth, underlying: underlying)
    }

    /// Runtime error.
    public static func runtime(
        _ code: RAErrorCode,
        _ message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        make(code: code, message: message, category: .internal, underlying: underlying)
    }
}

// MARK: - Common shortcuts

extension SDKException {
    /// Common shortcut: model not found.
    public static func modelNotFound(_ id: String) -> SDKException {
        make(code: .modelNotFound, message: "Model not found: \(id)", category: .model)
    }

    /// Common shortcut: not initialized.
    public static func notInitialized(_ what: String) -> SDKException {
        make(code: .notInitialized, message: "\(what) is not initialized", category: .component)
    }

    /// Common shortcut: invalid configuration.
    public static func invalidConfiguration(_ message: String) -> SDKException {
        make(code: .invalidConfiguration, message: message, category: .configuration)
    }

    /// Common shortcut: validation failed.
    public static func validationFailed(_ message: String) -> SDKException {
        make(code: .validationFailed, message: message, category: .validation)
    }

    /// Common shortcut: cancelled.
    public static func cancelled(_ message: String = "Operation cancelled") -> SDKException {
        make(code: .cancelled, message: message, category: .internal, shouldLog: false)
    }

    /// Common shortcut: not implemented.
    public static func notImplemented(_ message: String) -> SDKException {
        make(code: .notImplemented, message: message, category: .internal)
    }

    /// Common shortcut: timeout.
    public static func timeout(_ message: String) -> SDKException {
        make(code: .timeout, message: message, category: .network)
    }

    /// Common shortcut: network error.
    public static func networkError(_ message: String) -> SDKException {
        make(code: .networkError, message: message, category: .network)
    }
}

// MARK: - Conversion from arbitrary Error

extension SDKException {
    /// Convert any `Error` into an `SDKException`. If already one, returns it
    /// unchanged. Otherwise wraps in an unknown / general error.
    public static func from(_ error: any Error, category: RAErrorCategory = .internal) -> SDKException {
        if let ex = error as? SDKException { return ex }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return fromURLError(nsError, category: category)
        }
        return make(
            code: .unknown,
            message: error.localizedDescription,
            category: category,
            underlying: error
        )
    }

    public static func from(_ error: (any Error)?, category: RAErrorCategory = .internal) -> SDKException {
        guard let error = error else {
            return make(code: .unknown, message: "Unknown error", category: category)
        }
        return from(error, category: category)
    }

    private static func fromURLError(_ nsError: NSError, category: RAErrorCategory) -> SDKException {
        let code: RAErrorCode
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
            underlying: nsError
        )
    }
}

// MARK: - ONNX Runtime error mapping

extension SDKException {
    /// Map an ONNX Runtime C error code into an SDKException.
    public static func fromONNXCode(_ code: Int32) -> SDKException {
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

// MARK: - RAErrorCode classification helper

extension RAErrorCode {
    /// Whether this error is expected/routine and shouldn't be logged as error.
    public var isExpected: Bool {
        switch self {
        case .cancelled, .streamCancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Logging hook

extension SDKException {
    /// Log this exception to all configured destinations.
    public func log(file: String = #file, line: Int = #line, function: String = #function) {
        let level: LogLevel = (proto.code == .cancelled) ? .info : .error
        let fileName = (file as NSString).lastPathComponent

        var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "error_code": "\(proto.code)",
            "error_category": "\(proto.category)",
            "source_file": fileName,
            "source_line": line,
            "source_function": function
        ]

        if let underlying = underlying {
            metadata["underlying_error"] = String(describing: underlying)
        }
        if let reason = failureReason {
            metadata["failure_reason"] = reason
        }

        // Top SDK frames only (cheap and useful)
        let sdkFrames = stackTrace.filter { $0.contains("RunAnywhere") }.prefix(5)
        if !sdkFrames.isEmpty {
            metadata["stack_trace"] = sdkFrames.joined(separator: "\n")
        }

        Logging.shared.log(
            level: level,
            category: "\(proto.category)",
            message: proto.message,
            metadata: metadata
        )
    }
}

// MARK: - C ABI helpers

extension SDKException {
    /// Map a `rac_result_t` code to an SDKException, or nil on success.
    public var rawCABICode: Int32 {
        proto.cAbiCode
    }
}
