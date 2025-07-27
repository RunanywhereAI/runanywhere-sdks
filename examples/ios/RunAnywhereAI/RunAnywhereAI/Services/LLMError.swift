//
//  LLMError.swift
//  RunAnywhereAI
//

import Foundation

enum LLMError: LocalizedError {
    // Initialization errors
    case notInitialized(service: String? = nil)
    case initializationFailed(String)
    case modelNotFound
    case unsupportedFormat
    case invalidModelPath
    case modelLoadFailed(reason: String, framework: String)

    // Service errors
    case noServiceSelected
    case serviceNotAvailable(String)
    case frameworkNotSupported

    // Inference errors
    case inferenceError(String)
    case decodeFailed
    case tokenizationFailed
    case contextLengthExceeded

    // Memory errors
    case insufficientMemory
    case memoryAllocationFailed

    // Network errors
    case downloadFailed(String)
    case networkUnavailable

    // Other errors
    case notImplemented
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "The LLM service is not initialized. Please load a model first."
        case .initializationFailed(let reason):
            return "Failed to initialize the model: \(reason)"
        case .modelNotFound:
            return "The specified model file was not found."
        case .unsupportedFormat:
            return "This model format is not supported by the selected framework."
        case .invalidModelPath:
            return "The model path is invalid or inaccessible."
        case .modelLoadFailed(let reason, let framework):
            return "Failed to load model with \(framework): \(reason)"

        case .noServiceSelected:
            return "No LLM service is selected. Please select a framework first."
        case .serviceNotAvailable(let service):
            return "\(service) is not available on this device."
        case .frameworkNotSupported:
            return "This framework is not supported on the current iOS version."

        case .inferenceError(let reason):
            return "Inference failed: \(reason)"
        case .decodeFailed:
            return "Failed to decode the model output."
        case .tokenizationFailed:
            return "Failed to tokenize the input text."
        case .contextLengthExceeded:
            return "The input exceeds the maximum context length for this model."

        case .insufficientMemory:
            return "Not enough memory to load the model. Try using a smaller model or closing other apps."
        case .memoryAllocationFailed:
            return "Failed to allocate memory for the model."

        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .networkUnavailable:
            return "Network connection is not available."

        case .notImplemented:
            return "This feature is not yet implemented."
        case .unknown(let reason):
            return "An unknown error occurred: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Load a model before trying to generate text."
        case .initializationFailed:
            return "Check that the model file is valid and compatible with the selected framework."
        case .modelNotFound:
            return "Ensure the model file exists at the specified path."
        case .unsupportedFormat:
            return "Try using a different framework or convert the model to a supported format."
        case .invalidModelPath:
            return "Check the model path and ensure the app has permission to access it."
        case .modelLoadFailed:
            return "Ensure the model file is valid and compatible with the selected framework."

        case .noServiceSelected:
            return "Select a framework from the Models tab."
        case .serviceNotAvailable:
            return "Try using a different framework that's compatible with your device."
        case .frameworkNotSupported:
            return "Update to a newer iOS version or use a different framework."

        case .inferenceError:
            return "Try reloading the model or using a different input."
        case .decodeFailed:
            return "The model output may be corrupted. Try reloading the model."
        case .tokenizationFailed:
            return "Try using simpler input text without special characters."
        case .contextLengthExceeded:
            return "Reduce the length of your input or use a model with longer context support."

        case .insufficientMemory:
            return "Close other apps, restart your device, or use a smaller quantized model."
        case .memoryAllocationFailed:
            return "Restart the app and try again with a smaller model."

        case .downloadFailed:
            return "Check your internet connection and try again."
        case .networkUnavailable:
            return "Connect to the internet and try again."

        case .notImplemented:
            return "This feature will be available in a future update."
        case .unknown:
            return "Try restarting the app. If the problem persists, please report this issue."
        }
    }
}

// MARK: - Error Recovery

protocol ErrorRecoverable {
    func canRecover(from error: LLMError) -> Bool
    func attemptRecovery(from error: LLMError) async throws
}

// MARK: - Error Handling Extensions

extension LLMService {
    func handleError(_ error: Error) -> LLMError {
        if let llmError = error as? LLMError {
            return llmError
        }

        // Convert common errors to LLMError
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                if nsError.code == NSFileNoSuchFileError {
                    return .modelNotFound
                } else if nsError.code == NSFileReadNoPermissionError {
                    return .invalidModelPath
                }
            case NSURLErrorDomain:
                if nsError.code == NSURLErrorNotConnectedToInternet {
                    return .networkUnavailable
                } else if nsError.code == NSURLErrorTimedOut {
                    return .downloadFailed("Request timed out")
                }
            default:
                break
            }
        }

        return .unknown(error.localizedDescription)
    }
}
