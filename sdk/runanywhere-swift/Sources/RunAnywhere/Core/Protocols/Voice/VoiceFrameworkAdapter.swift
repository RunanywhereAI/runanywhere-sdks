import Foundation

/// Protocol for voice framework adapters
public protocol VoiceFrameworkAdapter {
    /// Framework identifier
    var framework: LLMFramework { get }

    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }

    /// Check if adapter can handle model
    func canHandle(model: ModelInfo) -> Bool

    /// Create voice service instance
    func createService() -> VoiceService

    /// Load model and return service
    func loadModel(_ model: ModelInfo) async throws -> VoiceService
}
