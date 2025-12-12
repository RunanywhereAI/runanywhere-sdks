//
//  TTSServiceProvider.swift
//  RunAnywhere SDK
//
//  Provider protocol for Text-to-Speech services (plugin architecture)
//

import Foundation

/// Protocol for TTS service providers (plugins)
///
/// External modules can implement this protocol to provide TTS capabilities.
/// Providers are registered with `ModuleRegistry` and selected based on
/// model compatibility and priority.
///
/// Example implementation:
/// ```swift
/// public class ONNXTTSProvider: TTSServiceProvider {
///     public var name: String { "ONNX TTS" }
///     public var version: String { "1.0.0" }
///
///     public func canHandle(modelId: String?) -> Bool {
///         guard let modelId = modelId else { return false }
///         return modelId.contains("piper") || modelId.contains("vits")
///     }
///
///     public func createTTSService(configuration: TTSConfiguration) async throws -> TTSService {
///         return ONNXTTSService(configuration: configuration)
///     }
/// }
/// ```
public protocol TTSServiceProvider {
    /// Create a TTS service instance for the given configuration
    /// - Parameter configuration: TTS configuration
    /// - Returns: A configured TTSService instance
    func createTTSService(configuration: TTSConfiguration) async throws -> TTSService

    /// Check if this provider can handle the given model/voice
    /// - Parameter modelId: Optional model identifier to check
    /// - Returns: True if this provider can handle the model
    func canHandle(modelId: String?) -> Bool

    /// Provider name for logging and debugging
    var name: String { get }

    /// Provider version
    var version: String { get }
}
