import Foundation
import RunAnywhere

/// Service provider for WhisperCPP STT capabilities
///
/// This provider integrates with ModuleRegistry to enable WhisperCPP-based speech-to-text
/// through the standard STTComponent interface.
///
/// Usage:
/// ```swift
/// import WhisperCPPRuntime
///
/// // In your app initialization:
/// await WhisperCPPSTTServiceProvider.register()
/// ```
public struct WhisperCPPSTTServiceProvider: STTServiceProvider {
    private static let logger = SDKLogger(category: "WhisperCPPServiceProvider")

    public let name: String = "WhisperCPP"
    public let version: String = "1.7.2"

    public init() {}

    public func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        Self.logger.info("Creating WhisperCPP STT service for model: \(configuration.modelId ?? "unknown")")

        // Get the actual model file path from the model registry
        var modelPath: String?
        if let modelId = configuration.modelId {
            // Query all available models and find the one we need
            let allModels = try await RunAnywhere.availableModels()
            let modelInfo = allModels.first { $0.id == modelId }

            // Check if model is downloaded and has a local path
            if let localPath = modelInfo?.localPath {
                modelPath = localPath.path
                Self.logger.info("Found local model path: \(modelPath ?? "nil")")
            } else {
                // Model not downloaded yet
                Self.logger.error("Model '\(modelId)' is not downloaded. Please download the model first.")
                throw SDKError.modelNotFound("Model '\(modelId)' is not downloaded. Please download the model before using it.")
            }
        }

        let service = WhisperCPPSTTService()
        try await service.initialize(modelPath: modelPath)
        return service
    }

    public func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        Self.logger.debug("Checking if can handle STT model: \(modelId)")

        // PRIMARY CHECK: Use cached model info from the registry (most reliable)
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            // Check if WhisperCPP is the preferred framework for STT
            if modelInfo.preferredFramework == .whisperCpp && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has whisperCpp as preferred framework for STT")
                return true
            }

            // Check if WhisperCPP is in compatible frameworks for speech models
            if modelInfo.compatibleFrameworks.contains(.whisperCpp) && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has whisperCpp in compatible frameworks for STT")
                return true
            }

            // Check if format is GGML (native whisper.cpp format)
            if modelInfo.format == .ggml && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has GGML format for STT (whisper.cpp compatible)")
                return true
            }

            // Model info exists but doesn't indicate WhisperCPP STT compatibility
            Self.logger.debug("Model \(modelId) found in cache but not WhisperCPP STT compatible")
            return false
        }

        // FALLBACK: Pattern-based matching for models not yet in cache
        let lowercased = modelId.lowercased()

        // Handle GGML whisper models (primary format for whisper.cpp)
        if lowercased.contains("ggml") && lowercased.contains("whisper") {
            Self.logger.debug("Model \(modelId) matches GGML Whisper pattern (fallback)")
            return true
        }

        // Handle .bin whisper models (GGML format)
        if lowercased.contains("whisper") && lowercased.hasSuffix(".bin") {
            Self.logger.debug("Model \(modelId) matches Whisper .bin pattern (fallback)")
            return true
        }

        // Handle explicit whispercpp references
        if lowercased.contains("whispercpp") || lowercased.contains("whisper-cpp") || lowercased.contains("whisper_cpp") {
            Self.logger.debug("Model \(modelId) matches WhisperCPP pattern (fallback)")
            return true
        }

        // Handle whisper model size patterns (tiny, base, small, medium, large)
        // These often indicate GGML models: whisper-tiny, whisper-base-q5_1, etc.
        let whisperSizePattern = #"whisper[_-]?(tiny|base|small|medium|large|turbo)"#
        if let regex = try? NSRegularExpression(pattern: whisperSizePattern, options: [.caseInsensitive]),
           regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) != nil {
            // Only match if it looks like a GGML model (not ONNX)
            if !lowercased.contains("onnx") && !lowercased.contains("sherpa") {
                Self.logger.debug("Model \(modelId) matches Whisper size pattern (fallback)")
                return true
            }
        }

        Self.logger.debug("Model \(modelId) does not match any WhisperCPP STT patterns")
        return false
    }

    /// Register this provider with the ModuleRegistry
    @MainActor
    public static func register(priority: Int = 90) async {
        logger.info("Registering WhisperCPP STT provider with priority \(priority)")
        let provider = WhisperCPPSTTServiceProvider()
        ModuleRegistry.shared.registerSTT(provider, priority: priority)
        logger.info("WhisperCPP STT provider registered")
    }
}

// MARK: - Auto Registration Support

/// Automatic registration when module is imported
public enum WhisperCPPModule {
    /// Call this to automatically register WhisperCPP with the SDK
    @MainActor
    public static func autoRegister() async {
        await WhisperCPPSTTServiceProvider.register()
    }
}
