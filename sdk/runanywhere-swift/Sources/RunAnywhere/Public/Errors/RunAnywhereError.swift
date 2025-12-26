//
//  RunAnywhereError.swift
//  RunAnywhere SDK
//
//  Main public error type for the RunAnywhere SDK.
//  Designed for clarity, debuggability, and crash reporter compatibility.
//

import Foundation

// MARK: - Error Domain

/// The error domain for all RunAnywhere SDK errors.
/// Used by crash reporters (Sentry, Crashlytics) and NSError bridging.
public let RunAnywhereErrorDomain = "com.runanywhere.sdk"

// MARK: - RunAnywhereError

/// Main public error type for the RunAnywhere SDK.
///
/// This error type is designed to be:
/// - **Clear**: Descriptive error messages with recovery suggestions
/// - **Type-safe**: Swift enum with associated values
/// - **Debuggable**: Full NSError bridging for crash reporters
/// - **Testable**: Equatable conformance for unit tests
/// - **Concurrent**: Sendable for async/await usage
///
/// ## Usage
/// ```swift
/// do {
///     try await RunAnywhere.loadModel("my-model")
/// } catch let error as RunAnywhereError {
///     print(error.errorDescription)
///     print(error.recoverySuggestion)
/// }
/// ```
public enum RunAnywhereError: LocalizedError, CustomNSError, Equatable, Sendable {

    // MARK: - Initialization Errors (1xxx)

    /// SDK not initialized. Call `RunAnywhere.initialize()` first.
    case notInitialized

    /// SDK already initialized. No action needed.
    case alreadyInitialized

    /// Invalid configuration provided.
    case invalidConfiguration(String)

    /// Invalid or missing API key.
    case invalidAPIKey(String?)

    /// Environment configuration mismatch (e.g., production key in debug build).
    case environmentMismatch(String)

    // MARK: - Model Errors (2xxx)

    /// Model with the specified identifier was not found.
    case modelNotFound(String)

    /// Failed to load the model.
    case modelLoadFailed(String, underlyingMessage: String?)

    /// Generic loading failure.
    case loadingFailed(String)

    /// Model validation failed with specific errors.
    case modelValidationFailed(String, [String])

    /// Model is incompatible with the current device/configuration.
    case modelIncompatible(String, String)

    // MARK: - Generation Errors (3xxx)

    /// Text generation failed.
    case generationFailed(String)

    /// Generation timed out.
    case generationTimeout(String?)

    /// Input context exceeds model's maximum context length.
    case contextTooLong(provided: Int, maximum: Int)

    /// Requested tokens exceed the maximum allowed.
    case tokenLimitExceeded(requested: Int, maximum: Int)

    /// Estimated cost exceeds the configured limit.
    case costLimitExceeded(estimated: Double, limit: Double)

    // MARK: - Network Errors (4xxx)

    /// Network connection is unavailable.
    case networkUnavailable

    /// Network error occurred.
    case networkError(String)

    /// HTTP request failed.
    case requestFailed(message: String)

    /// Download failed.
    case downloadFailed(url: String, message: String?)

    /// Server returned an error.
    case serverError(String)

    /// Operation timed out.
    case timeout(String)

    // MARK: - Storage Errors (5xxx)

    /// Insufficient storage space available.
    case insufficientStorage(required: Int64, available: Int64)

    /// Device storage is full.
    case storageFull

    /// Storage operation failed.
    case storageError(String)

    // MARK: - Hardware Errors (6xxx)

    /// Required hardware feature is not supported.
    case hardwareUnsupported(String)

    // MARK: - Component Errors (7xxx)

    /// Component is not initialized.
    case componentNotInitialized(String)

    /// Component is not ready for use.
    case componentNotReady(String)

    /// Invalid state for the requested operation.
    case invalidState(String)

    // MARK: - Validation Errors (8xxx)

    /// Input validation failed.
    case validationFailed(String)

    /// Requested modality is not supported.
    case unsupportedModality(String)

    // MARK: - Authentication Errors (9xxx)

    /// Authentication failed.
    case authenticationFailed(String)

    // MARK: - Framework Errors (10xxx)

    /// Required framework is not available.
    case frameworkNotAvailable(String)

    // MARK: - Feature Errors (11xxx)

    /// Feature is not available.
    case featureNotAvailable(String)

    /// Feature is not yet implemented.
    case notImplemented(String)

    // MARK: - CustomNSError (for Crash Reporters)

    /// The error domain for NSError bridging.
    public static var errorDomain: String { RunAnywhereErrorDomain }

    /// Machine-readable error code for programmatic handling and crash reports.
    public var errorCode: Int {
        switch self {
        // Initialization (1xxx)
        case .notInitialized: return 1001
        case .alreadyInitialized: return 1002
        case .invalidConfiguration: return 1003
        case .invalidAPIKey: return 1004
        case .environmentMismatch: return 1005

        // Model (2xxx)
        case .modelNotFound: return 2001
        case .modelLoadFailed: return 2002
        case .loadingFailed: return 2003
        case .modelValidationFailed: return 2004
        case .modelIncompatible: return 2005

        // Generation (3xxx)
        case .generationFailed: return 3001
        case .generationTimeout: return 3002
        case .contextTooLong: return 3003
        case .tokenLimitExceeded: return 3004
        case .costLimitExceeded: return 3005

        // Network (4xxx)
        case .networkUnavailable: return 4001
        case .networkError: return 4002
        case .requestFailed: return 4003
        case .downloadFailed: return 4004
        case .serverError: return 4005
        case .timeout: return 4006

        // Storage (5xxx)
        case .insufficientStorage: return 5001
        case .storageFull: return 5002
        case .storageError: return 5003

        // Hardware (6xxx)
        case .hardwareUnsupported: return 6001

        // Component (7xxx)
        case .componentNotInitialized: return 7001
        case .componentNotReady: return 7002
        case .invalidState: return 7003

        // Validation (8xxx)
        case .validationFailed: return 8001
        case .unsupportedModality: return 8002

        // Authentication (9xxx)
        case .authenticationFailed: return 9001

        // Framework (10xxx)
        case .frameworkNotAvailable: return 10001

        // Feature (11xxx)
        case .featureNotAvailable: return 11001
        case .notImplemented: return 11002
        }
    }

    /// Additional user info for NSError bridging.
    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]

        if let description = errorDescription {
            userInfo[NSLocalizedDescriptionKey] = description
        }
        if let reason = failureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = reason
        }
        if let suggestion = recoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }

        return userInfo
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        // Initialization
        case .notInitialized:
            return "RunAnywhere SDK is not initialized."
        case .alreadyInitialized:
            return "RunAnywhere SDK is already initialized."
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        case .invalidAPIKey(let reason):
            return reason.map { "Invalid API key: \($0)" } ?? "Invalid or missing API key."
        case .environmentMismatch(let reason):
            return "Environment mismatch: \(reason)"

        // Model
        case .modelNotFound(let id):
            return "Model '\(id)' not found."
        case .modelLoadFailed(let id, let message):
            return message.map { "Failed to load model '\(id)': \($0)" } ?? "Failed to load model '\(id)'."
        case .loadingFailed(let reason):
            return "Loading failed: \(reason)"
        case .modelValidationFailed(let id, let errors):
            return "Model '\(id)' validation failed: \(errors.joined(separator: ", "))"
        case .modelIncompatible(let id, let reason):
            return "Model '\(id)' is incompatible: \(reason)"

        // Generation
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .generationTimeout(let reason):
            return reason.map { "Generation timed out: \($0)" } ?? "Generation timed out."
        case .contextTooLong(let provided, let maximum):
            return "Context too long: \(provided) tokens (max: \(maximum))."
        case .tokenLimitExceeded(let requested, let maximum):
            return "Token limit exceeded: \(requested) requested (max: \(maximum))."
        case .costLimitExceeded(let estimated, let limit):
            return "Cost limit exceeded: $\(String(format: "%.2f", estimated)) (limit: $\(String(format: "%.2f", limit)))."

        // Network
        case .networkUnavailable:
            return "Network unavailable."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .downloadFailed(let url, let message):
            return message.map { "Download failed from '\(url)': \($0)" } ?? "Download failed from '\(url)'."
        case .serverError(let reason):
            return "Server error: \(reason)"
        case .timeout(let reason):
            return "Timeout: \(reason)"

        // Storage
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            return "Insufficient storage: \(formatter.string(fromByteCount: required)) required, \(formatter.string(fromByteCount: available)) available."
        case .storageFull:
            return "Device storage is full."
        case .storageError(let reason):
            return "Storage error: \(reason)"

        // Hardware
        case .hardwareUnsupported(let feature):
            return "Hardware doesn't support: \(feature)"

        // Component
        case .componentNotInitialized(let name):
            return "Component '\(name)' not initialized."
        case .componentNotReady(let name):
            return "Component '\(name)' not ready."
        case .invalidState(let reason):
            return "Invalid state: \(reason)"

        // Validation
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .unsupportedModality(let modality):
            return "Unsupported modality: \(modality)"

        // Authentication
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"

        // Framework
        case .frameworkNotAvailable(let name):
            return "Framework '\(name)' not available."

        // Feature
        case .featureNotAvailable(let name):
            return "Feature '\(name)' not available."
        case .notImplemented(let name):
            return "Feature '\(name)' not implemented."
        }
    }

    public var failureReason: String? {
        switch self {
        case .notInitialized:
            return "The SDK must be initialized before use."
        case .alreadyInitialized:
            return "Initialize can only be called once."
        case .invalidConfiguration:
            return "The provided configuration contains invalid values."
        case .invalidAPIKey:
            return "The API key is missing or invalid."
        case .environmentMismatch:
            return "The environment doesn't match the build configuration."
        case .modelNotFound:
            return "The model identifier doesn't match any available model."
        case .modelLoadFailed:
            return "The model file could not be loaded into memory."
        case .loadingFailed:
            return "A required resource could not be loaded."
        case .modelValidationFailed:
            return "The model file failed integrity checks."
        case .modelIncompatible:
            return "The model requires capabilities not available on this device."
        case .generationFailed:
            return "The model failed to generate output."
        case .generationTimeout:
            return "Generation took longer than the allowed time."
        case .contextTooLong:
            return "The input exceeds the model's context window."
        case .tokenLimitExceeded:
            return "The requested output length exceeds limits."
        case .costLimitExceeded:
            return "The estimated cost exceeds the configured budget."
        case .networkUnavailable:
            return "No network connection is available."
        case .networkError, .requestFailed, .serverError:
            return "A network communication error occurred."
        case .downloadFailed:
            return "The file could not be downloaded."
        case .timeout:
            return "The operation exceeded the time limit."
        case .insufficientStorage, .storageFull, .storageError:
            return "There is not enough storage space."
        case .hardwareUnsupported:
            return "Required hardware capabilities are not available."
        case .componentNotInitialized, .componentNotReady:
            return "A required component is not available."
        case .invalidState:
            return "The operation is not valid in the current state."
        case .validationFailed, .unsupportedModality:
            return "The input parameters are invalid."
        case .authenticationFailed:
            return "Authentication credentials are invalid."
        case .frameworkNotAvailable:
            return "A required system framework is not available."
        case .featureNotAvailable, .notImplemented:
            return "The requested feature is not available."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Call RunAnywhere.initialize() before using the SDK."
        case .alreadyInitialized:
            return "The SDK is ready to use."
        case .invalidConfiguration:
            return "Check your configuration and ensure all required fields are valid."
        case .invalidAPIKey:
            return "Provide a valid API key in your configuration."
        case .environmentMismatch:
            return "Use the appropriate API key for your build configuration."

        case .modelNotFound:
            return "Check the model ID or download the model first."
        case .modelLoadFailed, .loadingFailed:
            return "Ensure the model file is not corrupted. Try re-downloading."
        case .modelValidationFailed:
            return "Delete and re-download the model."
        case .modelIncompatible:
            return "Use a model compatible with your device."

        case .generationFailed:
            return "Check your input and try again."
        case .generationTimeout:
            return "Try a shorter prompt or reduce max tokens."
        case .contextTooLong:
            return "Shorten your input or use a model with larger context."
        case .tokenLimitExceeded:
            return "Reduce the max tokens setting."
        case .costLimitExceeded:
            return "Increase your cost limit or use a smaller model."

        case .networkUnavailable, .networkError, .requestFailed, .serverError:
            return "Check your internet connection and try again."
        case .downloadFailed:
            return "Check your connection and storage space, then retry."
        case .timeout:
            return "Try again or check your network connection."

        case .insufficientStorage, .storageFull, .storageError:
            return "Free up storage space and try again."

        case .hardwareUnsupported, .frameworkNotAvailable:
            return "This feature requires different hardware or OS version."

        case .componentNotInitialized, .componentNotReady:
            return "Wait for initialization to complete."
        case .invalidState:
            return "Ensure operations are called in the correct order."

        case .validationFailed, .unsupportedModality:
            return "Check your input parameters."

        case .authenticationFailed:
            return "Verify your credentials and try again."

        case .featureNotAvailable, .notImplemented:
            return "This feature may be available in a future update."
        }
    }

    // MARK: - Equatable

    public static func == (lhs: RunAnywhereError, rhs: RunAnywhereError) -> Bool {
        // Compare by error code for simple equality
        // This allows testing without matching associated values exactly
        lhs.errorCode == rhs.errorCode
    }
}

// MARK: - Type Alias

/// Convenience alias for RunAnywhereError.
public typealias SDKError = RunAnywhereError

// MARK: - Error Conversion

extension Error {
    /// Convert any error to RunAnywhereError for consistent API.
    ///
    /// If the error is already a RunAnywhereError, returns it directly.
    /// Otherwise, attempts to map common error types to appropriate cases.
    public func asRunAnywhereError() -> RunAnywhereError {
        // Already our error type
        if let raError = self as? RunAnywhereError {
            return raError
        }

        // Map URLError
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .timeout("Network request timed out")
            default:
                return .networkError(urlError.localizedDescription)
            }
        }

        // Map NSError with known domains
        let nsError = self as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return .networkError(nsError.localizedDescription)
        case NSCocoaErrorDomain where nsError.code == NSFileNoSuchFileError:
            return .storageError("File not found")
        case NSPOSIXErrorDomain where nsError.code == ENOSPC:
            return .storageFull
        default:
            return .requestFailed(message: localizedDescription)
        }
    }
}

// MARK: - Deprecated Compatibility

extension RunAnywhereError {
    /// Creates a modelLoadFailed error from an optional Error.
    /// - Parameters:
    ///   - identifier: The model identifier
    ///   - error: The optional underlying error
    /// - Returns: A modelLoadFailed error
    public static func modelLoadFailed(_ identifier: String, _ error: Error?) -> RunAnywhereError {
        .modelLoadFailed(identifier, underlyingMessage: error?.localizedDescription)
    }

    /// Creates a downloadFailed error from an optional Error.
    /// - Parameters:
    ///   - url: The download URL
    ///   - error: The optional underlying error
    /// - Returns: A downloadFailed error
    public static func downloadFailed(_ url: String, _ error: Error?) -> RunAnywhereError {
        .downloadFailed(url: url, message: error?.localizedDescription)
    }

    /// Creates a requestFailed error from an Error.
    /// - Parameter error: The underlying error
    /// - Returns: A requestFailed error
    public static func requestFailed(_ error: Error) -> RunAnywhereError {
        .requestFailed(message: error.localizedDescription)
    }
}
