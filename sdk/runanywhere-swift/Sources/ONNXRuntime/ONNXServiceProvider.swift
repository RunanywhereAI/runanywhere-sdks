import Foundation
import RunAnywhere

/// Service provider for ONNX Runtime STT capabilities
public struct ONNXSTTServiceProvider: STTServiceProvider {
    private static let logger = SDKLogger(category: "ONNXServiceProvider")

    public let name: String = "ONNX Runtime"
    public let version: String = "1.23.2"

    public init() {}

    public func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        Self.logger.info("Creating ONNX Runtime STT service for model: \(configuration.modelId ?? "unknown")")

        // Get the actual model file path from the model registry
        var modelPath: String? = nil
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

        let service = ONNXSTTService()
        try await service.initialize(modelPath: modelPath)
        return service
    }

    public func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return false }

        Self.logger.debug("Checking if can handle STT model: \(modelId)")

        // PRIMARY CHECK: Use cached model info from the registry (most reliable)
        if let modelInfo = ModelInfoCache.shared.modelInfo(for: modelId) {
            // Check if ONNX is the preferred framework for STT
            if modelInfo.preferredFramework == .onnx && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has ONNX as preferred framework for STT")
                return true
            }

            // Check if ONNX is in compatible frameworks for speech models
            if modelInfo.compatibleFrameworks.contains(.onnx) && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has ONNX in compatible frameworks for STT")
                return true
            }

            // Check if format is ONNX
            if modelInfo.format == .onnx && modelInfo.category == .speechRecognition {
                Self.logger.debug("Model \(modelId) has ONNX format for STT")
                return true
            }

            // Model info exists but doesn't indicate ONNX STT compatibility
            Self.logger.debug("Model \(modelId) found in cache but not ONNX STT compatible")
            return false
        }

        // FALLBACK: Pattern-based matching for models not yet in cache
        let lowercased = modelId.lowercased()

        // Explicitly handle ONNX models
        if lowercased.contains("onnx") || lowercased.hasSuffix(".onnx") {
            Self.logger.debug("Model \(modelId) matches ONNX pattern (fallback)")
            return true
        }

        // Handle Sherpa-ONNX models (zipformer, sherpa-whisper)
        if lowercased.contains("zipformer") || lowercased.contains("sherpa") {
            Self.logger.debug("Model \(modelId) matches Sherpa-ONNX pattern (fallback)")
            return true
        }

        Self.logger.debug("Model \(modelId) does not match any ONNX STT patterns")
        return false
    }

    /// Register this provider with the ModuleRegistry
    @MainActor
    public static func register(priority: Int = 100) async {
        logger.info("Registering ONNX Runtime STT provider with priority \(priority)")
        let provider = ONNXSTTServiceProvider()
        ModuleRegistry.shared.registerSTT(provider, priority: priority)
        logger.info("ONNX Runtime STT provider registered")
    }
}
