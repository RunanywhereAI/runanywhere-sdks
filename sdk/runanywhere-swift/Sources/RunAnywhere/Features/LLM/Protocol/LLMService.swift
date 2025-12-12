//
//  LLMService.swift
//  RunAnywhere SDK
//
//  Protocol defining Language Model service capabilities
//

import Foundation

/// Protocol for language model services
public protocol LLMService: AnyObject {

    // MARK: - Initialization

    /// Initialize the LLM service with optional model path
    /// - Parameter modelPath: Path to the model file (optional)
    func initialize(modelPath: String?) async throws

    // MARK: - Core Operations

    /// Generate text from prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Generated text
    func generate(prompt: String, options: LLMGenerationOptions) async throws -> String

    /// Stream generation token by token
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    ///   - onToken: Callback for each generated token
    func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws

    // MARK: - State

    /// Whether the service is ready for generation
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    // MARK: - Lifecycle

    /// Clean up resources
    func cleanup() async
}

// MARK: - Default Implementation

extension LLMService {
    /// Default implementation for streaming - falls back to non-streaming
    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        // Default implementation: generate full response and emit as single token
        let response = try await generate(prompt: prompt, options: options)
        onToken(response)
    }
}
