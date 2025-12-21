//
//  LLMService.swift
//  RunAnywhere SDK
//
//  Protocol defining Language Model service capabilities
//

import Foundation

/// Protocol for language model services
public protocol LLMService: AnyObject { // swiftlint:disable:this avoid_any_object

    // MARK: - Framework Identification

    /// The inference framework used by this service.
    /// Required for analytics and performance tracking.
    var inferenceFramework: InferenceFrameworkType { get }

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

    /// The context length (context window size) being used by the model.
    /// Returns nil if not available or not yet initialized.
    var contextLength: Int? { get }

    /// Whether the service supports true streaming generation (token-by-token)
    /// Services that don't support streaming should return false.
    /// When false, calling `streamGenerate` may result in `LLMError.streamingNotSupported`.
    var supportsStreaming: Bool { get }

    // MARK: - Lifecycle

    /// Clean up resources
    func cleanup() async

    /// Cancel any ongoing generation
    /// This is a best-effort operation; not all backends support mid-generation cancellation
    func cancel() async
}

// MARK: - Default Implementation

extension LLMService {
    /// Default: context length is unknown unless explicitly provided
    public var contextLength: Int? { nil }

    /// Default: streaming is not supported unless explicitly declared
    public var supportsStreaming: Bool { false }

    /// Default implementation for streaming - falls back to non-streaming
    /// Note: This is not true streaming, just a convenience fallback.
    /// Services with real streaming support should override this AND set `supportsStreaming = true`.
    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        // Default implementation: generate full response and emit as single token
        // This is NOT true streaming - just a compatibility fallback
        let response = try await generate(prompt: prompt, options: options)
        onToken(response)
    }

    /// Default implementation: no-op cancellation
    /// Services that support cancellation should override this
    public func cancel() async {
        // Default: no-op - most services don't support mid-generation cancellation
    }
}
