import Foundation
import RunAnywhere
import os

/// WhisperKit provider for Speech-to-Text services
///
/// Usage:
/// ```swift
/// import WhisperKitTranscription
///
/// // In your app initialization:
/// WhisperKitServiceProvider.register()
/// ```
public final class WhisperKitServiceProvider: STTServiceProvider {
    private let logger = Logger(subsystem: "com.runanywhere.whisperkit", category: "WhisperKitServiceProvider")

    // MARK: - Singleton for easy registration

    public static let shared = WhisperKitServiceProvider()

    /// Super simple registration - just call this in your app
    public static func register() {
        Task { @MainActor in
            ModuleRegistry.shared.registerSTT(shared)
        }
    }

    // MARK: - STTServiceProvider Protocol

    public var name: String {
        "WhisperKit"
    }

    public func canHandle(modelId: String?) -> Bool {
        // WhisperKit can handle whisper models
        guard let modelId = modelId else { return true }

        // Check if it's a whisper model
        let whisperPrefixes = ["whisper", "openai-whisper", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "whisper-large"]
        return whisperPrefixes.contains(where: { modelId.lowercased().contains($0) })
    }

    public func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        logger.info("Creating WhisperKit STT service")

        // Create and initialize the service
        let service = WhisperKitService()

        // Initialize with model path if provided
        if let modelId = configuration.modelId {
            logger.info("Initializing with model: \(modelId)")
            try await service.initialize(modelPath: modelId)
        } else {
            logger.info("Initializing with default model")
            try await service.initialize(modelPath: nil)
        }

        logger.info("WhisperKit service created successfully")
        return service
    }

    // MARK: - Private initializer to enforce singleton

    private init() {
        logger.info("WhisperKitServiceProvider initialized")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
public enum WhisperKitModule {
    /// Call this to automatically register WhisperKit with the SDK
    public static func autoRegister() {
        WhisperKitServiceProvider.register()
    }
}
