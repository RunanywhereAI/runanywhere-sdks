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
        let memoryRequired = modelInfo.memoryRequired ?? 1024 * 1024 * 1024 // Default 1GB if not specified
        let canAllocate = try await memoryService.canAllocate(memoryRequired)
        if !canAllocate {
            throw SDKError.loadingFailed("Insufficient memory")
        }

        // Determine modality based on model (for now, default to textToText for LLMs)
        let modality: FrameworkModality = modelInfo.preferredFramework == .whisperKit ? .voiceToText : .textToText

        // Find all adapters that can handle this model
        logger.info("🚀 Finding adapters for model (modality: \(modality))")
        let adapters = await adapterRegistry.findAllAdapters(for: modelInfo, modality: modality)

        guard !adapters.isEmpty else {
            logger.error("❌ No adapter found for model with preferred framework: \(modelInfo.preferredFramework?.rawValue ?? "none")")
            logger.error("❌ Compatible frameworks: \(modelInfo.compatibleFrameworks.map { $0.rawValue })")
            throw SDKError.frameworkNotAvailable(
                modelInfo.preferredFramework ?? .coreML
            )
        }

        logger.info("✅ Found \(adapters.count) adapter(s) capable of loading this model")

        // Try to load with each adapter (primary + fallbacks)
        var lastError: Error?
        for (index, adapter) in adapters.enumerated() {
            let isPrimary = index == 0
            logger.info(isPrimary ? "🚀 Trying primary adapter: \(adapter.framework.rawValue)" : "🔄 Trying fallback adapter: \(adapter.framework.rawValue)")

            do {
                let service = try await adapter.loadModel(modelInfo, for: modality)
                logger.info("✅ Model loaded successfully with \(adapter.framework.rawValue)")

                // Cast to LLMService
                guard let llmService = service as? LLMService else {
                    throw SDKError.loadingFailed("Adapter returned incompatible service type")
                }

                // Create loaded model
                let loaded = LoadedModel(model: modelInfo, service: llmService)

                // Register loaded model
                memoryService.registerLoadedModel(
                    loaded,
                    size: modelInfo.memoryRequired ?? memoryRequired,
                    service: llmService
                )
                loadedModels[modelId] = loaded

                return loaded
            } catch {
                logger.error("❌ Failed to load model with \(adapter.framework.rawValue): \(error.localizedDescription)")
                lastError = error
                // Continue to next adapter
            }
        }

        // All adapters failed
        logger.error("❌ All adapters failed to load model")
        throw lastError ?? SDKError.loadingFailed("Failed to load model with any available adapter")
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
