import Foundation

// MARK: - Pipeline Extensions

public extension RunAnywhere {

    /// Create a modular voice pipeline from a unified voice configuration
    /// This is the recommended way to create voice pipelines
    static func createVoicePipeline(config: VoiceConfiguration) async throws -> ModularVoicePipelineService {
        guard RunAnywhere.isSDKInitialized else {
            throw SDKError.notInitialized
        }

        // Convert to ModularPipelineConfig and delegate to service
        let modularConfig = ModularPipelineConfig(voiceConfig: config)
        return try await serviceContainer.voiceCapabilityService.createModularPipeline(config: modularConfig)
    }

    /// Create a modular voice pipeline from low-level configuration
    /// Use the VoiceConfiguration-based method instead for better ergonomics
    static func createVoicePipeline(config: ModularPipelineConfig) async throws -> ModularVoicePipelineService {
        guard RunAnywhere.isSDKInitialized else {
            throw SDKError.notInitialized
        }

        // Delegate to the voice capability service
        return try await serviceContainer.voiceCapabilityService.createModularPipeline(config: config)
    }
}
