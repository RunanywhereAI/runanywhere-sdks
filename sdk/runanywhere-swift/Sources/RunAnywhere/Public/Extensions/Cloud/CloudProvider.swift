//
//  CloudProvider.swift
//  RunAnywhere SDK
//
//  Protocol for cloud AI providers (OpenAI-compatible APIs).
//

import Foundation

// MARK: - Cloud Provider Protocol

/// Protocol for cloud AI inference providers.
///
/// Conform to this protocol to add a custom cloud provider for hybrid routing.
/// The SDK ships with `OpenAICompatibleProvider` which works with any
/// OpenAI-compatible API (OpenAI, Groq, Together, Ollama, etc.).
///
/// Example:
/// ```swift
/// let provider = OpenAICompatibleProvider(
///     apiKey: "sk-...",
///     model: "gpt-4o-mini"
/// )
/// RunAnywhere.registerCloudProvider(provider)
/// ```
public protocol CloudProvider: Sendable {

    /// Unique identifier for this provider
    var providerId: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// Generate text (non-streaming)
    func generate(
        prompt: String,
        options: CloudGenerationOptions
    ) async throws -> CloudGenerationResult

    /// Generate text with streaming
    func generateStream(
        prompt: String,
        options: CloudGenerationOptions
    ) -> AsyncThrowingStream<String, Error>

    /// Check if the provider is available and configured
    func isAvailable() async -> Bool
}
