import Foundation
import RunAnywhereSDK
import LLM

public class LLMSwiftAdapter: FrameworkAdapter {
    public var framework: LLMFramework { .llamaCpp }

    public var supportedFormats: [ModelFormat] {
        [.gguf, .ggml]
    }

    private var hardwareConfig: HardwareConfiguration?

    public init() {}

    public func canHandle(model: ModelInfo) -> Bool {
        // Check format support
        guard supportedFormats.contains(model.format) else { return false }

        // Check quantization compatibility
        if let quantization = model.metadata?["quantization"] as? String {
            return isQuantizationSupported(quantization)
        }

        // Check memory requirements
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return model.estimatedMemory < Int64(Double(availableMemory) * 0.7)
    }

    public func createService() -> LLMService {
        return LLMSwiftService(hardwareConfig: hardwareConfig)
    }

    public func loadModel(_ model: ModelInfo) async throws -> LLMService {
        guard let localPath = model.localPath else {
            throw FrameworkError(
                framework: framework,
                underlying: LLMServiceError.modelNotLoaded,
                context: "Model not downloaded at expected path"
            )
        }

        let service = LLMSwiftService(hardwareConfig: hardwareConfig)
        try await service.initialize(modelPath: localPath.path)
        return service
    }

    public func configure(with hardware: HardwareConfiguration) async {
        self.hardwareConfig = hardware
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        // GGUF models use approximately their file size in memory
        // Add 20% overhead for context and processing
        let baseSize = model.estimatedMemory
        let overhead = Int64(Double(baseSize) * 0.2)
        return baseSize + overhead
    }

    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        // Determine optimal configuration based on model size
        let hasGPU = HardwareCapabilityManager.shared.hasGPU()
        let modelSize = model.estimatedMemory

        let preferredAccelerator: HardwareAccelerator = {
            if hasGPU && modelSize < 4_000_000_000 { // 4GB
                return .gpu
            } else {
                return .cpu
            }
        }()

        return HardwareConfiguration(
            preferredAccelerator: preferredAccelerator,
            maxMemoryUsage: estimateMemoryUsage(for: model),
            powerEfficiencyMode: .balanced
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
