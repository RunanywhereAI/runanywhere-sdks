import Foundation

/// SDK-specific errors
public enum SDKError: LocalizedError {
    case notInitialized
    case notImplemented
    case modelNotFound(String)
    case loadingFailed(String)
    case generationFailed(String)
    case generationTimeout(String)
    case frameworkNotAvailable(LLMFramework)
    case downloadFailed(Error)
    case validationFailed(ValidationError)
    case routingFailed(String)
    case databaseInitializationFailed(Error)
    case unsupportedModality(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK not initialized. Call initialize(with:) first."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .modelNotFound(let model):
            return "Model '\(model)' not found."
        case .loadingFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .generationTimeout(let reason):
            return "Generation timed out: \(reason)"
        case .frameworkNotAvailable(let framework):
            return "Framework \(framework.rawValue) not available"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .validationFailed(let error):
            return "Validation failed: \(error.localizedDescription)"
        case .routingFailed(let reason):
            return "Routing failed: \(reason)"
        case .databaseInitializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"
        case .unsupportedModality(let modality):
            return "Unsupported modality: \(modality)"
        }
    }
}
