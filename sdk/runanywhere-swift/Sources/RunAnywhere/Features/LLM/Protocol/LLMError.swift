//
//  LLMError.swift
//  RunAnywhere SDK
//
//  Typed errors for LLM operations
//

import Foundation

/// Errors that can occur during LLM operations
public enum LLMError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// Service not initialized before use
    case notInitialized

    /// No provider found for the requested model
    case noProviderFound(modelId: String?)

    /// Model file not found at path
    case modelNotFound(path: String)

    /// Service failed to initialize
    case initializationFailed(underlying: Error)

    // MARK: - Generation Errors

    /// Generation failed with underlying error
    case generationFailed(Error)

    /// Generation timed out
    case generationTimeout(message: String)

    /// Context length exceeded
    case contextLengthExceeded(maxLength: Int, requestedLength: Int)

    /// Invalid generation options
    case invalidOptions(reason: String)

    // MARK: - Streaming Errors

    /// Streaming generation is not supported by this service
    case streamingNotSupported

    /// Stream was cancelled
    case streamCancelled

    // MARK: - Resource Errors

    /// Insufficient memory for model
    case insufficientMemory(required: Int64, available: Int64)

    /// Service is busy processing another request
    case serviceBusy

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "LLM service is not initialized. Call initialize() first."
        case .noProviderFound(let modelId):
            if let modelId = modelId {
                return "No LLM provider found for model: \(modelId)"
            }
            return "No LLM provider registered. Register one with ModuleRegistry.shared.registerLLM(provider)."
        case .modelNotFound(let path):
            return "Model not found at path: \(path)"
        case .initializationFailed(let error):
            return "LLM initialization failed: \(error.localizedDescription)"
        case .generationFailed(let error):
            return "Generation failed: \(error.localizedDescription)"
        case .generationTimeout(let message):
            return "Generation timed out: \(message)"
        case .contextLengthExceeded(let maxLength, let requestedLength):
            return "Context length exceeded. Maximum: \(maxLength), Requested: \(requestedLength)"
        case .invalidOptions(let reason):
            return "Invalid generation options: \(reason)"
        case .streamingNotSupported:
            return "Streaming generation is not supported by this service"
        case .streamCancelled:
            return "Stream generation was cancelled"
        case .insufficientMemory(let required, let available):
            return "Insufficient memory. Required: \(required) bytes, Available: \(available) bytes"
        case .serviceBusy:
            return "LLM service is busy processing another request"
        }
    }
}
