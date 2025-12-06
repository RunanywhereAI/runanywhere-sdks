import Foundation
import RunAnywhere

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
    private let logger = SDKLogger(category: "WhisperKitServiceProvider")

    // MARK: - Singleton for easy registration

    public static let shared = WhisperKitServiceProvider()

    /// Super simple registration - just call this in your app
    @MainActor
    public static func register() {
        ModuleRegistry.shared.registerSTT(shared)
    }

    // MARK: - STTServiceProvider Protocol

    public var name: String {
        "WhisperKit"
    }

    public func canHandle(modelId: String?) -> Bool {
        // WhisperKit can handle whisper models
        guard let modelId = modelId else { return false }

        logger.debug("Checking if can handle STT model: \(modelId)")

        // PRIMARY CHECK: Use cached model info from the registry (most reliable)
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            // Check if WhisperKit is the preferred framework for STT
            if modelInfo.preferredFramework == .whisperKit && modelInfo.category == .speechRecognition {
                logger.debug("Model \(modelId) has WhisperKit as preferred framework for STT")
                return true
            }

            // Check if WhisperKit is in compatible frameworks for speech models
            if modelInfo.compatibleFrameworks.contains(.whisperKit) && modelInfo.category == .speechRecognition {
                logger.debug("Model \(modelId) has WhisperKit in compatible frameworks for STT")
                return true
            }

            // Explicitly exclude ONNX-preferred models
            if modelInfo.preferredFramework == .onnx || modelInfo.format == .onnx {
                logger.debug("Model \(modelId) is ONNX-preferred, not handling with WhisperKit")
                return false
            }

            // Model info exists but doesn't indicate WhisperKit STT compatibility
            logger.debug("Model \(modelId) found in cache but not WhisperKit STT compatible")
            return false
        }

        // FALLBACK: Pattern-based matching for models not yet in cache
        let lowercased = modelId.lowercased()

        // Exclude ONNX models - they should be handled by ONNXServiceProvider
        if lowercased.contains("onnx") || lowercased.contains("glados") || lowercased.contains("distil") {
            logger.debug("Model \(modelId) matches ONNX pattern, not handling with WhisperKit")
            return false
        }

        // Check if it's a whisper model
        let whisperPrefixes = ["whisper", "openai-whisper", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "whisper-large"]
        if whisperPrefixes.contains(where: { lowercased.contains($0) }) {
            logger.debug("Model \(modelId) matches Whisper pattern (fallback)")
            return true
        }

        logger.debug("Model \(modelId) does not match any WhisperKit STT patterns")
        return false
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
    @MainActor
    public static func autoRegister() {
        WhisperKitServiceProvider.register()
    }
}
