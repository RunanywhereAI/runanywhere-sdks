import Foundation

/// Errors related to framework operations
public enum FrameworkError: LocalizedError {
    case notAvailable(String)
    case initializationFailed(String)
    case modelLoadFailed(String)
    case inferenceError(String)
    case unsupportedOperation(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let framework):
            return "Framework not available: \(framework)"
        case .initializationFailed(let reason):
            return "Framework initialization failed: \(reason)"
        case .modelLoadFailed(let reason):
            return "Model loading failed: \(reason)"
        case .inferenceError(let reason):
            return "Inference error: \(reason)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .configurationError(let reason):
            return "Framework configuration error: \(reason)"
        }
    }
}
