import Foundation

/// LLM.swift specific errors
public enum LLMSwiftError: LocalizedError {
    case modelLoadFailed
    case initializationFailed
    case generationFailed(String)
    case templateResolutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the LLM model"
        case .initializationFailed:
            return "Failed to initialize LLM service"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .templateResolutionFailed(let reason):
            return "Template resolution failed: \(reason)"
        }
    }
}
