import Foundation

/// Unified protocol for all framework adapters (LLM, Voice, Image, etc.)
public protocol UnifiedFrameworkAdapter {
    /// The framework this adapter handles
    var framework: LLMFramework { get }

    /// The modalities this adapter supports
    var supportedModalities: Set<FrameworkModality> { get }

    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }

    /// Check if this adapter can handle a specific model
    /// - Parameter model: The model information
    /// - Returns: Whether this adapter can handle the model
    func canHandle(model: ModelInfo) -> Bool

    /// Create a service instance based on the modality
    /// - Parameter modality: The modality to create a service for
    /// - Returns: A service instance (LLMService, VoiceService, etc.)
    func createService(for modality: FrameworkModality) -> Any?

    /// Load a model using this adapter
    /// - Parameters:
    ///   - model: The model to load
    ///   - modality: The modality to use
    /// - Returns: A service instance with the loaded model
    func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any

    /// Configure the adapter with hardware settings
    /// - Parameter hardware: Hardware configuration
    func configure(with hardware: HardwareConfiguration) async

    /// Estimate memory usage for a model
    /// - Parameter model: The model to estimate
    /// - Returns: Estimated memory in bytes
    func estimateMemoryUsage(for model: ModelInfo) -> Int64

    /// Get optimal hardware configuration for a model
    /// - Parameter model: The model to configure for
    /// - Returns: Optimal hardware configuration
    func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration
}

/// Extension to provide default implementations
public extension UnifiedFrameworkAdapter {
    /// Default implementation that returns the framework's supported modalities
    var supportedModalities: Set<FrameworkModality> {
        return framework.supportedModalities
    }
}
