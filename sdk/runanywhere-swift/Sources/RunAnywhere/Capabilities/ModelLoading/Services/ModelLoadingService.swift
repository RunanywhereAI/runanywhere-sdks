import Foundation

/// Service responsible for loading models
public class ModelLoadingService {
    private let registry: ModelRegistry
    private let adapterRegistry: FrameworkAdapterRegistry
    private let validationService: ValidationService
    private let memoryService: MemoryManager // Using MemoryManager protocol for now

    private var loadedModels: [String: LoadedModel] = [:]

    public init(
        registry: ModelRegistry,
        adapterRegistry: FrameworkAdapterRegistry,
        validationService: ValidationService,
        memoryService: MemoryManager
    ) {
        self.registry = registry
        self.adapterRegistry = adapterRegistry
        self.validationService = validationService
        self.memoryService = memoryService
    }

    /// Load a model by identifier
    public func loadModel(_ modelId: String) async throws -> LoadedModel {
        // Check if already loaded
        if let loaded = loadedModels[modelId] {
            return loaded
        }

        // Get model info from registry
        guard let modelInfo = registry.getModel(by: modelId) else {
            throw SDKError.modelNotFound(modelId)
        }

        // Validate model file exists
        guard let localPath = modelInfo.localPath else {
            throw SDKError.modelNotFound("Model '\(modelId)' not downloaded")
        }

        // Validate model
        let validationResult = try await validationService.validate(localPath)
        if !validationResult.errors.isEmpty {
            throw SDKError.validationFailed(validationResult.errors.first!)
        }

        // Check memory availability
        let canAllocate = try await memoryService.canAllocate(modelInfo.estimatedMemory)
        if !canAllocate {
            throw SDKError.loadingFailed("Insufficient memory")
        }

        // Find appropriate adapter
        guard let adapter = adapterRegistry.findBestAdapter(for: modelInfo) else {
            throw SDKError.frameworkNotAvailable(
                modelInfo.preferredFramework ?? .coreML
            )
        }

        // Load model through adapter
        let service = try await adapter.loadModel(modelInfo)

        // Register loaded model
        try await memoryService.registerModel(
            modelId: modelId,
            memory: modelInfo.estimatedMemory
        )

        let loaded = LoadedModel(model: modelInfo, service: service)
        loadedModels[modelId] = loaded

        return loaded
    }

    /// Unload a model
    public func unloadModel(_ modelId: String) async throws {
        guard let loaded = loadedModels[modelId] else {
            return
        }

        // Unload through service
        await loaded.service.unload()

        // Unregister from memory service
        await memoryService.unregisterModel(modelId: modelId)

        // Remove from loaded models
        loadedModels.removeValue(forKey: modelId)
    }

    /// Get currently loaded model
    public func getLoadedModel(_ modelId: String) -> LoadedModel? {
        return loadedModels[modelId]
    }
}
