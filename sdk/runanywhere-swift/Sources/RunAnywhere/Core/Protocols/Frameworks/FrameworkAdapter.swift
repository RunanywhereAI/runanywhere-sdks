import Foundation

/// Protocol for framework-specific adapters
public protocol FrameworkAdapter {
    /// The framework this adapter handles
    var framework: LLMFramework { get }

    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }

    /// Check if this adapter can handle a specific model
    /// - Parameter model: The model information
    /// - Returns: Whether this adapter can handle the model
    func canHandle(model: ModelInfo) -> Bool

    /// Create a service instance for this framework
    /// - Returns: An LLMService implementation
    func createService() -> LLMService

    /// Load a model using this adapter
    /// - Parameter model: The model to load
    /// - Returns: An LLMService instance with the loaded model
    func loadModel(_ model: ModelInfo) async throws -> LLMService

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
