//
//  RunAnywhereError.swift
//  RunAnywhere SDK
//
//  Main public error type for the RunAnywhere SDK
//  All SDK errors should use this type for consistent error handling
//

import Foundation

/// Main public error type for the RunAnywhere SDK
/// Conforms to SDKErrorProtocol for consistent error handling and analytics
public enum RunAnywhereError: LocalizedError, SDKErrorProtocol {
    // MARK: - Initialization Errors

    case notInitialized
    case alreadyInitialized
    case invalidConfiguration(String)
    case invalidAPIKey(String?)

    // MARK: - Model Errors

    case modelNotFound(String)
    case modelLoadFailed(String, Error?)
    case loadingFailed(String)
    case modelValidationFailed(String, [String])
    case modelIncompatible(String, String)

    // MARK: - Generation Errors

    case generationFailed(String)
    case generationTimeout(String?)
    case contextTooLong(Int, Int)
    case tokenLimitExceeded(Int, Int)
    case costLimitExceeded(Double, Double)

    // MARK: - Network Errors

    case networkUnavailable
    case networkError(String)
    case requestFailed(Error)
    case downloadFailed(String, Error?)
    case serverError(String)
    case timeout(String)

    // MARK: - Storage Errors

    case insufficientStorage(Int64, Int64)
    case storageFull
    case storageError(String)

    // MARK: - Hardware Errors

    case hardwareUnsupported(String)

    // MARK: - Component Errors

    case componentNotInitialized(String)
    case componentNotReady(String)
    case invalidState(String)

    // MARK: - Validation Errors

    case validationFailed(String)
    case unsupportedModality(String)

    // MARK: - Authentication Errors

    case authenticationFailed(String)

    // MARK: - Framework Errors

    case frameworkNotAvailable(LLMFramework)
    case databaseInitializationFailed(Error)

    // MARK: - Feature Errors

    case featureNotAvailable(String)
    case notImplemented(String)

    // MARK: - SDKErrorProtocol Conformance

    public var code: ErrorCode {
        switch self {
        case .notInitialized: return .notInitialized
        case .alreadyInitialized: return .alreadyInitialized
        case .invalidConfiguration: return .invalidInput
        case .invalidAPIKey: return .apiKeyInvalid
        case .modelNotFound: return .modelNotFound
        case .modelLoadFailed: return .modelLoadFailed
        case .loadingFailed: return .modelLoadFailed
        case .modelValidationFailed: return .modelValidationFailed
        case .modelIncompatible: return .modelIncompatible
        case .generationFailed: return .generationFailed
        case .generationTimeout: return .generationTimeout
        case .contextTooLong: return .contextTooLong
        case .tokenLimitExceeded: return .tokenLimitExceeded
        case .costLimitExceeded: return .costLimitExceeded
        case .networkUnavailable: return .networkUnavailable
        case .networkError: return .apiError
        case .requestFailed: return .apiError
        case .downloadFailed: return .downloadFailed
        case .serverError: return .apiError
        case .timeout: return .networkTimeout
        case .insufficientStorage: return .insufficientStorage
        case .storageFull: return .storageFull
        case .storageError: return .fileAccessDenied
        case .hardwareUnsupported: return .hardwareUnsupported
        case .componentNotInitialized: return .notInitialized
        case .componentNotReady: return .notInitialized
        case .invalidState: return .invalidInput
        case .validationFailed: return .invalidInput
        case .unsupportedModality: return .invalidInput
        case .authenticationFailed: return .authenticationFailed
        case .frameworkNotAvailable: return .hardwareUnavailable
        case .databaseInitializationFailed: return .unknown
        case .featureNotAvailable: return .unknown
        case .notImplemented: return .unknown
        }
    }

    public var category: ErrorCategory {
        switch self {
        case .notInitialized, .alreadyInitialized, .invalidConfiguration, .invalidAPIKey:
            return .initialization
        case .modelNotFound, .modelLoadFailed, .loadingFailed, .modelValidationFailed, .modelIncompatible:
            return .model
        case .generationFailed, .generationTimeout, .contextTooLong, .tokenLimitExceeded, .costLimitExceeded:
            return .generation
        case .networkUnavailable, .networkError, .requestFailed, .downloadFailed, .serverError, .timeout:
            return .network
        case .insufficientStorage, .storageFull, .storageError:
            return .storage
        case .hardwareUnsupported:
            return .hardware
        case .componentNotInitialized, .componentNotReady, .invalidState:
            return .component
        case .validationFailed, .unsupportedModality:
            return .validation
        case .authenticationFailed:
            return .authentication
        case .frameworkNotAvailable, .databaseInitializationFailed:
            return .framework
        case .featureNotAvailable, .notImplemented:
            return .unknown
        }
    }

    public var underlyingError: Error? {
        switch self {
        case .modelLoadFailed(_, let error): return error
        case .requestFailed(let error): return error
        case .downloadFailed(_, let error): return error
        case .databaseInitializationFailed(let error): return error
        default: return nil
        }
    }

    // MARK: - LocalizedError Conformance

    public var errorDescription: String? {
        switch self {
        // Initialization
        case .notInitialized:
            return "RunAnywhere SDK is not initialized. Call initialize() first."
        case .alreadyInitialized:
            return "RunAnywhere SDK is already initialized."
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        case .invalidAPIKey(let reason):
            if let reason = reason {
                return "Invalid API key: \(reason)"
            }
            return "Invalid or missing API key."

        // Model errors
        case .modelNotFound(let identifier):
            return "Model '\(identifier)' not found."
        case .modelLoadFailed(let identifier, let error):
            if let error = error {
                return "Failed to load model '\(identifier)': \(error.localizedDescription)"
            }
            return "Failed to load model '\(identifier)'"
        case .loadingFailed(let reason):
            return "Failed to load: \(reason)"
        case .modelValidationFailed(let identifier, let errors):
            let errorList = errors.joined(separator: ", ")
            return "Model '\(identifier)' validation failed: \(errorList)"
        case .modelIncompatible(let identifier, let reason):
            return "Model '\(identifier)' is incompatible: \(reason)"

        // Generation errors
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        case .generationTimeout(let reason):
            if let reason = reason {
                return "Generation timed out: \(reason)"
            }
            return "Text generation timed out."
        case .contextTooLong(let provided, let maximum):
            return "Context too long: \(provided) tokens (maximum: \(maximum))"
        case .tokenLimitExceeded(let requested, let maximum):
            return "Token limit exceeded: requested \(requested), maximum \(maximum)"
        case .costLimitExceeded(let estimated, let limit):
            return "Cost limit exceeded: estimated $\(String(format: "%.2f", estimated)), limit $\(String(format: "%.2f", limit))"

        // Network errors
        case .networkUnavailable:
            return "Network connection unavailable."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .downloadFailed(let url, let error):
            if let error = error {
                return "Failed to download from '\(url)': \(error.localizedDescription)"
            }
            return "Failed to download from '\(url)'"
        case .serverError(let reason):
            return "Server error: \(reason)"
        case .timeout(let reason):
            return "Operation timed out: \(reason)"

        // Storage errors
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            let requiredStr = formatter.string(fromByteCount: required)
            let availableStr = formatter.string(fromByteCount: available)
            return "Insufficient storage: \(requiredStr) required, \(availableStr) available"
        case .storageFull:
            return "Device storage is full."
        case .storageError(let reason):
            return "Storage error: \(reason)"

        // Hardware errors
        case .hardwareUnsupported(let feature):
            return "Hardware does not support \(feature)."

        // Component errors
        case .componentNotInitialized(let component):
            return "Component not initialized: \(component)"
        case .componentNotReady(let component):
            return "Component not ready: \(component)"
        case .invalidState(let reason):
            return "Invalid state: \(reason)"

        // Validation errors
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .unsupportedModality(let modality):
            return "Unsupported modality: \(modality)"

        // Authentication errors
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"

        // Framework errors
        case .frameworkNotAvailable(let framework):
            return "Framework \(framework.rawValue) not available"
        case .databaseInitializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"

        // Feature errors
        case .featureNotAvailable(let feature):
            return "Feature '\(feature)' is not available."
        case .notImplemented(let feature):
            return "Feature '\(feature)' is not yet implemented."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Call RunAnywhere.initialize() before using the SDK."
        case .alreadyInitialized:
            return "The SDK is already initialized. You can use it directly."
        case .invalidConfiguration:
            return "Check your configuration settings and ensure all required fields are provided."
        case .invalidAPIKey:
            return "Provide a valid API key in the configuration."

        case .modelNotFound:
            return "Check the model identifier or download the model first."
        case .modelLoadFailed, .loadingFailed:
            return "Ensure the model file is not corrupted and is compatible with your device."
        case .modelValidationFailed:
            return "The model file may be corrupted or incompatible. Try re-downloading."
        case .modelIncompatible:
            return "Use a different model that is compatible with your device."

        case .generationFailed:
            return "Check your input and try again."
        case .generationTimeout:
            return "Try with a shorter prompt or fewer tokens."
        case .contextTooLong:
            return "Reduce the context size or use a model with larger context window."
        case .tokenLimitExceeded:
            return "Reduce the number of tokens requested."
        case .costLimitExceeded:
            return "Increase your cost limit or use a more cost-effective model."

        case .networkUnavailable, .networkError, .requestFailed, .serverError:
            return "Check your internet connection and try again."
        case .downloadFailed:
            return "Check your internet connection and available storage space."
        case .timeout:
            return "The operation timed out. Try again or check your network connection."

        case .insufficientStorage, .storageError:
            return "Free up storage space on your device."
        case .storageFull:
            return "Delete unnecessary files to free up space."

        case .hardwareUnsupported, .frameworkNotAvailable:
            return "Use a different model or device that supports this feature."

        case .componentNotInitialized, .componentNotReady:
            return "Ensure the component is properly initialized before use."
        case .invalidState:
            return "Check the current state and ensure operations are called in the correct order."
        case .validationFailed, .unsupportedModality:
            return "Check your input parameters and ensure they are valid."

        case .authenticationFailed:
            return "Check your credentials and try again."
        case .databaseInitializationFailed:
            return "Try reinstalling the app or clearing app data."

        case .featureNotAvailable, .notImplemented:
            return "This feature may be available in a future update."
        }
    }
}

// MARK: - Backward Compatibility Type Alias

/// Type alias for backward compatibility with code using SDKError
/// @available(*, deprecated, renamed: "RunAnywhereError")
public typealias SDKError = RunAnywhereError
