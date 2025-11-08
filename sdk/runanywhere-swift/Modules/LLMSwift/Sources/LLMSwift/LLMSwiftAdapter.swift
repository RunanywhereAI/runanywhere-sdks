import Foundation
import RunAnywhere
import LLM

public class LLMSwiftAdapter: UnifiedFrameworkAdapter {
    public let framework: LLMFramework = .llamaCpp

    public let supportedModalities: Set<FrameworkModality> = [.textToText]

    public let supportedFormats: [ModelFormat] = [.gguf, .ggml]

    private let logger = SDKLogger(category: "LLMSwiftAdapter")

    public init() {}

    public func canHandle(model: ModelInfo) -> Bool {
        // Check format support
        guard supportedFormats.contains(model.format) else { return false }

        // Check modality support
        guard supportedModalities.contains(model.modality) else { return false }

        // Check quantization compatibility
        if let metadata = model.metadata, let quantization = metadata.quantizationLevel {
            return isQuantizationSupported(quantization.rawValue)
        }

        // Check memory requirements
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return model.memoryRequired ?? 0 < Int64(Double(availableMemory) * 0.7)
    }

    public func createService(for modality: FrameworkModality) -> Any? {
        guard modality == .textToText else { return nil }
        return LLMSwiftService()
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        guard modality == .textToText else {
            throw SDKError.unsupportedModality(modality.rawValue)
        }
        logger.info("Loading model: \(model.name)")

        guard let localPath = model.localPath else {
            logger.error("Model has no local path - not downloaded")
            throw LLMServiceError.modelNotFound("Model not downloaded at expected path")
        }

        logger.debug("Creating LLMSwiftService with model path")

        let service = LLMSwiftService()
        logger.debug("Initializing service with model")
        try await service.initialize(modelPath: localPath.path)
        logger.info("Service initialized successfully")
        return service
    }


    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        // GGUF models use approximately their file size in memory
        // Add 20% overhead for context and processing
        let baseSize = model.memoryRequired ?? 0
        let overhead = Int64(Double(baseSize) * 0.2)
        return baseSize + overhead
    }

    public func configure(with hardware: HardwareConfiguration) async {
        // Configuration handled internally by LLMSwift
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        // Return default configuration - LLMSwift handles optimization internally
        return HardwareConfiguration(
            primaryAccelerator: .cpu,
            memoryMode: .balanced
        )
    }

    private func isQuantizationSupported(_ quantization: String) -> Bool {
        let supportedQuantizations = [
            "Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L",
            "Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M",
            "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M",
            "Q6_K", "Q8_0", "IQ2_XXS", "IQ2_XS",
            "IQ3_S", "IQ3_XXS", "IQ4_NL", "IQ4_XS"
        ]
        return supportedQuantizations.contains(quantization)
    }
}
