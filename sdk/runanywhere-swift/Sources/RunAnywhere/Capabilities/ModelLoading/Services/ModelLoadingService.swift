import Foundation

/// Service responsible for loading models
public class ModelLoadingService {
    private let registry: ModelRegistry
    private let adapterRegistry: AdapterRegistry
    private let memoryService: MemoryManager // Using MemoryManager protocol for now
    private let logger = SDKLogger(category: "ModelLoadingService")

    private var loadedModels: [String: LoadedModel] = [:]

    public init(
        registry: ModelRegistry,
        adapterRegistry: AdapterRegistry,
        memoryService: MemoryManager
    ) {
        self.registry = registry
        self.adapterRegistry = adapterRegistry
        self.memoryService = memoryService
    }

    /// Load a model by identifier
    public func loadModel(_ modelId: String) async throws -> LoadedModel {
        logger.info("🚀 Loading model: \(modelId)")

        // Check if already loaded
        if let loaded = loadedModels[modelId] {
            logger.info("✅ Model already loaded: \(modelId)")
            return loaded
        }

        // Get model info from registry
        guard let modelInfo = registry.getModel(by: modelId) else {
            logger.error("❌ Model not found in registry: \(modelId)")
            throw SDKError.modelNotFound(modelId)
        }

        logger.info("✅ Found model in registry: \(modelInfo.name)")

        // Check if this is a built-in model (e.g., Foundation Models)
        let isBuiltIn = modelInfo.localPath?.scheme == "builtin"

        if !isBuiltIn {
            // Check model file exists for non-built-in models
            guard modelInfo.localPath != nil else {
                throw SDKError.modelNotFound("Model '\(modelId)' not downloaded")
            }
        } else {
            logger.info("🏗️ Built-in model detected, skipping file check")
        }

        // Check memory availability
        let canAllocate = try await memoryService.canAllocate(modelInfo.memoryRequired)
        if !canAllocate {
            throw SDKError.loadingFailed("Insufficient memory")
        }

        // Find appropriate adapter
        logger.info("🚀 Finding adapter for model")

        guard let adapter = adapterRegistry.findBestAdapter(for: modelInfo) else {
            logger.error("❌ No adapter found for model with preferred framework: \(modelInfo.preferredFramework?.rawValue ?? "none")")
            logger.error("❌ Compatible frameworks: \(modelInfo.compatibleFrameworks.map { $0.rawValue })")
            throw SDKError.frameworkNotAvailable(
                modelInfo.preferredFramework ?? .coreML
            )
        }

        logger.info("✅ Found adapter for framework: \(adapter.framework.rawValue)")

        // Determine modality based on model (for now, default to textToText for LLMs)
        let modality: FrameworkModality = modelInfo.preferredFramework == .whisperKit ? .voiceToText : .textToText

        // Load model through adapter
        logger.info("🚀 Loading model through adapter")
        let service = try await adapter.loadModel(modelInfo, for: modality)
        logger.info("✅ Model loaded through adapter")

        // Cast to LLMService
        guard let llmService = service as? LLMService else {
            throw SDKError.loadingFailed("Adapter returned incompatible service type")
        }

        // Create loaded model
        let loaded = LoadedModel(model: modelInfo, service: llmService)

        // Register loaded model
        memoryService.registerLoadedModel(
            loaded,
            size: modelInfo.memoryRequired,
            service: llmService
        )
        loadedModels[modelId] = loaded

        return loaded
    }

    /// Unload a model
    public func unloadModel(_ modelId: String) async throws {
        guard let loaded = loadedModels[modelId] else {
            return
        }

        // Unload through service
        await loaded.service.cleanup()

        // Unregister from memory service
        memoryService.unregisterModel(modelId)

        // Remove from loaded models
        loadedModels.removeValue(forKey: modelId)
    }

    /// Get currently loaded model
    public func getLoadedModel(_ modelId: String) -> LoadedModel? {
        return loadedModels[modelId]
    }
}
