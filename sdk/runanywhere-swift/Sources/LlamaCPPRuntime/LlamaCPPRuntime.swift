import Foundation

/// LlamaCPP Runtime module for RunAnywhere SDK
///
/// This module provides LlamaCPP backend support for:
/// - Text Generation (LLM) using GGUF models
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
/// import LlamaCPPRuntime
///
/// let service = LlamaCPPService()
/// try await service.initialize(modelPath: "/path/to/model.gguf")
///
/// // Synchronous generation
/// let result = try await service.generate(prompt: "Hello, world!")
/// print("Generated: \(result)")
///
/// // Streaming generation
/// for try await token in service.generateStream(prompt: "Tell me a story") {
///     print(token, terminator: "")
/// }
/// ```
public enum LlamaCPPRuntime {
    /// Current version of the LlamaCPP Runtime module
    public static let version = "1.0.0"

    /// LlamaCPP library version
    public static let llamaCppVersion = "b5390"
}
