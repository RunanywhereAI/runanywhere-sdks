import Foundation
import RunAnywhereSDK

/// WhisperKit adapter for voice transcription
public class WhisperKitAdapter: UnifiedFrameworkAdapter {

    // MARK: - Properties

    public let framework: LLMFramework = .whisperKit

    public let supportedModalities: Set<FrameworkModality> = [.voiceToText]

    public let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    // MARK: - UnifiedFrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        return model.compatibleFrameworks.contains(.whisperKit)
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        guard modality == .voiceToText else { return nil }
        return WhisperKitService()
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        guard modality == .voiceToText else {
            throw SDKError.unsupportedModality(modality.rawValue)
        }

        let service = WhisperKitService()

        // Initialize with model path if available
        let modelPath = model.localPath?.path
        try await service.initialize(modelPath: modelPath)

        return service
    }

    public func configure(with hardware: HardwareConfiguration) async {
        // WhisperKit doesn't need special hardware configuration
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        return model.estimatedMemory
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        return HardwareConfiguration()
    }

    // MARK: - Initialization

    public init() {
        // No initialization needed for basic adapter
    }
}
