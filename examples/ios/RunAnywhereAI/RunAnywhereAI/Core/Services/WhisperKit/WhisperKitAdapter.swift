import Foundation
import RunAnywhereSDK

/// WhisperKit adapter for voice transcription
public class WhisperKitAdapter: VoiceFrameworkAdapter {

    // MARK: - Properties

    public let framework: LLMFramework = .whisperKit

    public let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    // MARK: - VoiceFrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        return model.compatibleFrameworks.contains(.whisperKit)
    }

    public func createService() -> VoiceService {
        return WhisperKitService()
    }

    public func loadModel(_ model: ModelInfo) async throws -> VoiceService {
        let service = WhisperKitService()

        // Initialize with model path if available
        let modelPath = model.localPath?.path
        try await service.initialize(modelPath: modelPath)

        return service
    }

    // MARK: - Initialization

    public init() {
        // No initialization needed for basic adapter
    }
}
