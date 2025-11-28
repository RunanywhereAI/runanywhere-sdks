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
        // Check if model ID indicates ONNX format
        guard let modelId = modelId else { return false }

        let lowercased = modelId.lowercased()

        Self.logger.debug("Checking if can handle model: \(modelId)")

        // Explicitly handle ONNX models (Glados/Distil-Whisper for STT)
        if lowercased.contains("onnx") || lowercased.hasSuffix(".onnx") {
            Self.logger.debug("Model \(modelId) matches ONNX pattern")
            return true
        }

        // Handle Sherpa-ONNX models (zipformer, sherpa-whisper)
        if lowercased.contains("zipformer") || lowercased.contains("sherpa") {
            Self.logger.debug("Model \(modelId) matches Sherpa-ONNX pattern")
            return true
        }

        // Handle Glados/Distil-Whisper models (these are ONNX-based)
        if lowercased.contains("glados") || lowercased.contains("distil") {
            Self.logger.debug("Model \(modelId) matches Glados/Distil pattern")
            return true
        }

        Self.logger.debug("Model \(modelId) does not match any ONNX patterns")
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
