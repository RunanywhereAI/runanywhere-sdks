import Foundation
import RunAnywhere

/// LlamaCPP Core adapter for RunAnywhere SDK
///
/// This adapter provides LLM text generation via the runanywhere-core LlamaCPP backend.
/// It uses the native C++ llama.cpp implementation via XCFramework for maximum performance.
public class LlamaCPPCoreAdapter: FrameworkAdapter {
    public let framework: LLMFramework = .llamaCpp

    public let supportedModalities: Set<FrameworkModality> = [.textToText]

    public let supportedFormats: [ModelFormat] = [.gguf, .ggml]

    private let logger = SDKLogger(category: "LlamaCPPCoreAdapter")

    // Service instance
    private var service: LlamaCPPService?

    public init() {}

    /// Register the LLM service provider with ModuleRegistry
    @MainActor
    public func onRegistration() {
        // Register LlamaCPP service provider with ModuleRegistry
        ModuleRegistry.shared.registerLLM(LlamaCPPServiceProvider.shared)
        logger.info("Registered LlamaCPPServiceProvider with ModuleRegistry")
    }

    public func canHandle(model: ModelInfo) -> Bool {
        // Check format support
        guard supportedFormats.contains(model.format) else { return false }

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
        return LlamaCPPService()
    }

    public func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any {
        guard modality == .textToText else {
            throw SDKError.unsupportedModality(modality.rawValue)
        }
        logger.info("Loading model via LlamaCPP Core: \(model.name)")

        guard let localPath = model.localPath else {
            logger.error("Model has no local path - not downloaded")
            throw LLMError.modelNotFound(path: "Model not downloaded at expected path")
        }

        logger.debug("Creating LlamaCPPService with model path: \(localPath.path)")

        let newService = LlamaCPPService()

        // Initialize the backend
        try await newService.initialize()

        // Load the model
        try await newService.loadModel(path: localPath.path)

        self.service = newService
        logger.info("LlamaCPP Core service initialized successfully with model")
        return newService
    }

    public func estimateMemoryUsage(for model: ModelInfo) -> Int64 {
        // GGUF models use approximately their file size in memory
        // Add 30% overhead for Metal buffers and KV cache
        let baseSize = model.memoryRequired ?? 0
        let overhead = Int64(Double(baseSize) * 0.3)
        return baseSize + overhead
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

// MARK: - LLM Service Conformance

extension LlamaCPPService: LLMService {
    // Note: isReady, currentModel, and initialize(modelPath:) are already defined in LlamaCPPService

    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> String {
        let config = LlamaCPPGenerationConfig(
            maxTokens: options.maxTokens,
            temperature: options.temperature,  // Already Float
            systemPrompt: nil  // System prompt handled at higher level
        )
        return try await generate(prompt: prompt, config: config)
    }

    public func streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        let config = LlamaCPPGenerationConfig(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
            systemPrompt: nil
        )

        for try await token in generateStream(prompt: prompt, config: config) {
            onToken(token)
        }
    }

    public func cleanup() async {
        try? await unloadModel()
    }
}
