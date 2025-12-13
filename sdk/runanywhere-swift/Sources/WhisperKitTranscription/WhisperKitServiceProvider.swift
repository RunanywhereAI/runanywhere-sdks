//
//  WhisperKitTranscription.swift
//  WhisperKitTranscription Module
//
//  Simple registration for WhisperKit STT services
//

import Foundation
import RunAnywhere

// MARK: - WhisperKit Module Registration

/// WhisperKit module for Speech-to-Text
///
/// Usage:
/// ```swift
/// import WhisperKitTranscription
///
/// // Register at app startup
/// WhisperKitModule.register()
///
/// // Then use via RunAnywhere
/// let text = try await RunAnywhere.transcribe(audioData)
/// ```
public enum WhisperKitModule {
    private static let logger = SDKLogger(category: "WhisperKit")

    /// Register WhisperKit STT service with the SDK
    @MainActor
    public static func register(priority: Int = 100) {
        ServiceRegistry.shared.registerSTT(
            name: "WhisperKit",
            priority: priority,
            canHandle: { modelId in
                canHandleModel(modelId)
            },
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("WhisperKit STT registered")
    }

    // MARK: - Private Helpers

    private static func canHandleModel(_ modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        let lowercased = modelId.lowercased()

        // Check model info cache first
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            if modelInfo.preferredFramework == .whisperKit && modelInfo.category == .speechRecognition {
                return true
            }
            if modelInfo.compatibleFrameworks.contains(.whisperKit) && modelInfo.category == .speechRecognition {
                return true
            }
            if modelInfo.preferredFramework == .onnx || modelInfo.format == .onnx {
                return false
            }
            return false
        }

        // Fallback: Pattern-based matching
        if lowercased.contains("onnx") || lowercased.contains("glados") || lowercased.contains("distil") {
            return false
        }

        let whisperPatterns = ["whisper", "openai-whisper", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "whisper-large"]
        return whisperPatterns.contains(where: { lowercased.contains($0) })
    }

    private static func createService(config: STTConfiguration) async throws -> STTService {
        logger.info("Creating WhisperKit STT service")

        let service = WhisperKitService()

        if let modelId = config.modelId {
            logger.info("Initializing with model: \(modelId)")
            try await service.initialize(modelPath: modelId)
        } else {
            logger.info("Initializing with default model")
            try await service.initialize(modelPath: nil)
        }

        logger.info("WhisperKit service created successfully")
        return service
    }
}
