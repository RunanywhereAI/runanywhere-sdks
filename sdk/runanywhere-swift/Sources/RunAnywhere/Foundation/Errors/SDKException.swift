//
//  SDKException.swift
//  RunAnywhere
//
//  Canonical Swift error type. Wraps the generated proto `RASDKError`
//  (Sources/RunAnywhere/Generated/errors.pb.swift) so Swift `throws` works
//  while keeping the wire-canonical proto as the source of truth.
//
//  Usage:
//      throw SDKException.modelNotFound("whisper-base")
//      throw SDKException(code: .notInitialized, message: "STT model not loaded", category: .component)
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
        var proto = RASDKError()
        proto.code = code
        proto.message = message
        proto.category = category
        // Round-trip C ABI code: positive proto code ↔ negative rac_result_t
        let raw = code.rawValue
        if raw > 0 && raw <= 899 {
            proto.cAbiCode = -Int32(raw)
        }
        if let unwrapped = underlying {
            proto.nestedMessage = String(describing: unwrapped)
        }
        self.proto = proto
        self.underlying = underlying
        self.stackTrace = Thread.callStackSymbols
    }

    // MARK: Convenience accessors

    public var code: RAErrorCode { proto.code }
    public var category: RAErrorCategory { proto.category }
    public var message: String { proto.message }

    /// Dot-separated path to the field that triggered a validation failure
    /// (e.g. `"STTOptions.sampleRate"`). Populated by the generated
    /// `validate()` helpers under `Sources/RunAnywhere/Generated/...` so
    /// callers can programmatically identify the failing field without
    /// parsing the human-readable message.
    ///
    /// Backed by the typed `context.fieldPath` proto field, which is the
    /// wire-canonical carrier shared with Kotlin / Dart / TS.
    public var fieldPath: String? {
        guard proto.hasContext, proto.context.hasFieldPath else { return nil }
        return proto.context.fieldPath
    }

    // MARK: LocalizedError

    public var errorDescription: String? {
        // Include the underlying "caused by" detail (e.g. the real backend/MLX
        // load error commons set via rac_error_set_details) when present, so
        // callers see the actual reason instead of only the generic per-code
        // message.
        let nested = proto.nestedMessage
        guard !nested.isEmpty, nested != proto.message else { return proto.message }
        return proto.message.isEmpty ? nested : "\(proto.message): \(nested)"
    }

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
        if let unwrapped = underlying {
            result += "\n  Caused by: \(unwrapped)"
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

    /// Validation failure with a structured `fieldPath` discriminant
    /// (e.g. `"STTOptions.sampleRate"`). Mirrors the canonical shape
    /// emitted by `idl/codegen/generate_*_convenience.py`: every SDK
    /// throws `{ code, category, fieldPath, message }`.
    public static func validationFailed(
        fieldPath: String,
        message: String,
        underlying: (any Error)? = nil
    ) -> SDKException {
        var context = RAErrorContext()
        context.fieldPath = fieldPath

        var proto = RASDKError()
        proto.code = .invalidArgument
        proto.category = .validation
        proto.message = message
        proto.context = context
        // Round-trip C ABI code: positive proto code ↔ negative rac_result_t.
        let raw = RAErrorCode.invalidArgument.rawValue
        if raw > 0 && raw <= 899 {
            proto.cAbiCode = -Int32(raw)
        }
        if let unwrapped = underlying {
            proto.nestedMessage = String(describing: unwrapped)
        }
        let ex = SDKException(proto: proto, underlying: underlying)
        if !RAErrorCode.invalidArgument.isExpected {
            ex.log()
        }
        return ex
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
        let raCode: RAErrorCode
        let message: String
        switch code {
        case 0:
            raCode = .unknown
            message = "Unexpected success code passed to error handler"
        case -1:
            raCode = .initializationFailed
            message = "ONNX Runtime initialization failed"
        case -2:
            raCode = .modelLoadFailed
            message = "Failed to load ONNX model"
        case -3:
            raCode = .generationFailed
            message = "ONNX inference failed"
        case -4:
            raCode = .invalidState
            message = "Invalid ONNX handle"
        case -5:
            raCode = .invalidInput
            message = "Invalid ONNX parameters"
        case -6:
            raCode = .insufficientMemory
            message = "ONNX Runtime out of memory"
        case -7:
            raCode = .notImplemented
            message = "ONNX feature not implemented"
        case -8:
            raCode = .cancelled
            message = "ONNX operation cancelled"
        case -9:
            raCode = .timeout
            message = "ONNX operation timed out"
        case -10:
            raCode = .storageError
            message = "ONNX IO error"
        default:
            raCode = .unknown
            message = "ONNX error code: \(code)"
        }
        return make(code: raCode, message: message, category: .internal)
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
        let level: RALogLevel = (proto.code == .cancelled) ? .info : .error
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
