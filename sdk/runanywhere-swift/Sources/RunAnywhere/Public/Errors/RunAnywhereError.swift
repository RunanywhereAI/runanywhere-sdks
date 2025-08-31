import Foundation

/// Main public error type for the RunAnywhere SDK
public enum RunAnywhereError: LocalizedError {
    // Initialization errors
    case notInitialized
    case alreadyInitialized
    case invalidConfiguration(String)
    case invalidAPIKey

    // Model errors
    case modelNotFound(String)
    case modelLoadFailed(String, Error?)
    case modelValidationFailed(String, [String])
    case modelIncompatible(String, String) // model, reason

    // Generation errors
    case generationFailed(String)
    case generationTimeout
    case contextTooLong(Int, Int) // provided, maximum
    case tokenLimitExceeded(Int, Int) // requested, maximum
    case costLimitExceeded(Double, Double) // estimated, limit

    // Network errors
    case networkUnavailable
    case requestFailed(Error)
    case downloadFailed(String, Error?)

    // Storage errors
    case insufficientStorage(Int64, Int64) // required, available
    case storageFull

    // Hardware errors
    case hardwareUnsupported(String)
    case memoryPressure
    case thermalStateExceeded

    // Feature errors
    case featureNotAvailable(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        // Initialization
        case .notInitialized:
            return "RunAnywhere SDK is not initialized. Call initialize() first."
        case .alreadyInitialized:
            return "RunAnywhere SDK is already initialized."
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        case .invalidAPIKey:
            return "Invalid or missing API key."

        // Model errors
        case .modelNotFound(let identifier):
            return "Model '\(identifier)' not found."
        case .modelLoadFailed(let identifier, let error):
            if let error = error {
                return "Failed to load model '\(identifier)': \(error.localizedDescription)"
            }
            return "Failed to load model '\(identifier)'"
        case .modelValidationFailed(let identifier, let errors):
            let errorList = errors.joined(separator: ", ")
            return "Model '\(identifier)' validation failed: \(errorList)"
        case .modelIncompatible(let identifier, let reason):
            return "Model '\(identifier)' is incompatible: \(reason)"

        // Generation errors
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        case .generationTimeout:
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
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .downloadFailed(let url, let error):
            if let error = error {
                return "Failed to download from '\(url)': \(error.localizedDescription)"
            }
            return "Failed to download from '\(url)'"

        // Storage errors
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            let requiredStr = formatter.string(fromByteCount: required)
            let availableStr = formatter.string(fromByteCount: available)
            return "Insufficient storage: \(requiredStr) required, \(availableStr) available"
        case .storageFull:
            return "Device storage is full."

        // Hardware errors
        case .hardwareUnsupported(let feature):
            return "Hardware does not support \(feature)."
        case .memoryPressure:
            return "System is under memory pressure."
        case .thermalStateExceeded:
            return "Device temperature too high for operation."

        // Feature errors
        case .featureNotAvailable(let feature):
            return "Feature '\(feature)' is not available."
        case .notImplemented(let feature):
            return "Feature '\(feature)' is not yet implemented."
        }
    }

    /// The recovery suggestion for the error
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
        case .modelLoadFailed:
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

        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .requestFailed:
            return "Check your network connection and try again."
        case .downloadFailed:
            return "Check your internet connection and available storage space."

        case .insufficientStorage:
            return "Free up storage space on your device."
        case .storageFull:
            return "Delete unnecessary files to free up space."

        case .hardwareUnsupported:
            return "Use a different model or device that supports this feature."
        case .memoryPressure:
            return "Close other apps to free up memory."
        case .thermalStateExceeded:
            return "Let your device cool down before continuing."

        case .featureNotAvailable:
            return "This feature may be available in a future update."
        case .notImplemented:
            return "This feature is coming soon."
        }
    }
}
