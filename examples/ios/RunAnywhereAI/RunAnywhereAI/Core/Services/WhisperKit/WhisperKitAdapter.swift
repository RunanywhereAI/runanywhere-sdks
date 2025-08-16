import Foundation
import RunAnywhereSDK
import os

/// WhisperKit adapter for voice transcription
public class WhisperKitAdapter: UnifiedFrameworkAdapter {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "WhisperKitAdapter")

    // MARK: - Properties

    public let framework: LLMFramework = .whisperKit

    public let supportedModalities: Set<FrameworkModality> = [.voiceToText, .textToVoice]

    public let supportedFormats: [ModelFormat] = [.mlmodel, .mlpackage]

    // MARK: - UnifiedFrameworkAdapter Implementation

    public func canHandle(model: ModelInfo) -> Bool {
        let canHandle = model.compatibleFrameworks.contains(.whisperKit)
        logger.debug("canHandle(\(model.name, privacy: .public)): \(canHandle)")
        return canHandle
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        logger.info("createService for modality: \(modality.rawValue, privacy: .public)")
        switch modality {
        case .voiceToText:
            logger.info("Creating WhisperKitService for voice-to-text")
            return WhisperKitService()
        case .textToVoice:
            logger.info("Creating SystemTTSServiceWrapper for text-to-voice")
            return SystemTTSServiceWrapper()
        default:
            logger.warning("Unsupported modality: \(modality.rawValue, privacy: .public)")
            return nil
        }
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        logger.info("loadModel(\(model.name, privacy: .public)) for modality: \(modality.rawValue, privacy: .public)")
        switch modality {
        case .voiceToText:
            logger.info("Creating and initializing WhisperKitService...")
            let service = WhisperKitService()
            // Initialize with model path if available
            let modelPath = model.localPath?.path
            logger.debug("Model path: \(modelPath ?? "nil", privacy: .public)")
            try await service.initialize(modelPath: modelPath)
            logger.info("WhisperKitService initialized")
            return service
        case .textToVoice:
            // TTS doesn't need model loading, just return the service
            logger.info("Creating SystemTTSServiceWrapper (no model loading needed)")
            return SystemTTSServiceWrapper()
        default:
            logger.error("Unsupported modality: \(modality.rawValue, privacy: .public)")
            throw SDKError.unsupportedModality(modality.rawValue)
        }
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
        logger.info("WhisperKitAdapter initialized")
        logger.info("Supported modalities: \(self.supportedModalities.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
        logger.info("Supported formats: \(self.supportedFormats.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
        // No initialization needed for basic adapter
    }
}
