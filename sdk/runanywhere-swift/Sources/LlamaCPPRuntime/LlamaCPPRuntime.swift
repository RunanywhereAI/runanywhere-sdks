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
    /// Note: Should be kept in sync with SDK version in VERSION file
    public static let version = "0.16.0"

    /// LlamaCPP library version (underlying C++ library)
    public static let llamaCppVersion = "b5390"
}
