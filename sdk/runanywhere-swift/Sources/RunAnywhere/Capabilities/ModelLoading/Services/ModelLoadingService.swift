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
        print("🚀 [ModelLoadingService] Loading model: \(modelId)")

        // Check if already loaded
        if let loaded = loadedModels[modelId] {
            print("✅ [ModelLoadingService] Model already loaded: \(modelId)")
            return loaded
        }

        // Get model info from registry
        guard let modelInfo = registry.getModel(by: modelId) else {
            print("❌ [ModelLoadingService] Model not found in registry: \(modelId)")
            throw SDKError.modelNotFound(modelId)
        }

        print("✅ [ModelLoadingService] Found model in registry: \(modelInfo.name)")

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
        print("🚀 [ModelLoadingService] Finding adapter for model")
        let registeredAdapters = adapterRegistry.getRegisteredAdapters()
        print("📊 [ModelLoadingService] Registered adapters: \(registeredAdapters.keys.map { $0.rawValue })")

        guard let adapter = adapterRegistry.findBestAdapter(for: modelInfo) else {
            print("❌ [ModelLoadingService] No adapter found for model with preferred framework: \(modelInfo.preferredFramework?.rawValue ?? "none")")
            print("❌ [ModelLoadingService] Compatible frameworks: \(modelInfo.compatibleFrameworks.map { $0.rawValue })")
            throw SDKError.frameworkNotAvailable(
                modelInfo.preferredFramework ?? .coreML
            )
        }

        print("✅ [ModelLoadingService] Found adapter for framework: \(adapter.framework.rawValue)")

        // Load model through adapter
        print("🚀 [ModelLoadingService] Loading model through adapter")
        let service = try await adapter.loadModel(modelInfo)
        print("✅ [ModelLoadingService] Model loaded through adapter")

        // Create loaded model
        let loaded = LoadedModel(model: modelInfo, service: service)

        // Register loaded model
        memoryService.registerLoadedModel(
            loaded,
            size: modelInfo.estimatedMemory,
            service: service
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
