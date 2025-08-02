import Foundation

/// Dynamic model registry with discovery capabilities
/// Backward compatibility wrapper for modular registry system
public class DynamicModelRegistry: ModelRegistry {
    public static let shared: DynamicModelRegistry = DynamicModelRegistry()

    private var registeredModels: [String: ModelInfo] = [:]
    private let modelLock: NSLock = NSLock()
    private let discovery: ModelDiscovery
    private let updater: RegistryUpdater
    private let storage: RegistryStorage
    private let cache: RegistryCache

    public typealias DiscoveryConfig = RunAnywhere.DiscoveryConfig

    /// Configuration for model discovery
    public struct DiscoveryConfig {
        public var includeLocalModels: Bool = true
        public var includeOnlineModels: Bool = true
        public var modelDirectories: [URL] = []
        public var cacheTimeout: TimeInterval = 3600 // 1 hour

        public init() {
            // Add default model directories
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                modelDirectories.append(documentsURL.appendingPathComponent("Models", isDirectory: true))
            }
        }
    }

    private init() {
        self.discovery = ModelDiscovery()
        self.storage = RegistryStorage()
        self.cache = RegistryCache()
        self.updater = RegistryUpdater(discovery: discovery, storage: storage)
        setupDefaultProviders()
    }

    /// Configure the registry
    public func configure(_ config: DiscoveryConfig) {
        updater.configure(config)
    }

    /// Register a model provider
    public func registerProvider(_ provider: ModelProvider) {
        updater.registerProvider(provider)
    }

    // MARK: - Model Discovery

    public func discoverModels() async -> [ModelInfo] {
        let discoveredModels = await updater.updateRegistry()

        // Update local registry
        modelLock.lock()
        for model in discoveredModels {
            registeredModels[model.id] = model
            cache.set(model)
        }
        modelLock.unlock()

        return discoveredModels
    }

    // Discovery functionality delegated to modular components

    // MARK: - Model Registration

    public func registerModel(_ model: ModelInfo) {
        modelLock.lock()
        registeredModels[model.id] = model
        modelLock.unlock()

        cache.set(model)

        // Persist to storage in background
        Task {
            await storage.saveModel(model)
        }
    }

    public func removeModel(_ modelId: String) {
        modelLock.lock()
        registeredModels.removeValue(forKey: modelId)
        modelLock.unlock()

        cache.remove(modelId)

        // Remove from storage in background
        Task {
            await storage.removeModel(modelId)
        }
    }

    public func getModel(by modelId: String) -> ModelInfo? {
        // Try cache first
        if let cachedModel = cache.get(modelId) {
            return cachedModel
        }

        modelLock.lock()
        defer { modelLock.unlock() }
        return registeredModels[modelId]
    }

    public func updateModel(_ model: ModelInfo) {
        registerModel(model)
    }

    // MARK: - Model Filtering

    public func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        // Use cache if available and valid
        if cache.isCacheValid() {
            return cache.filterModels(by: criteria)
        }

        // Fall back to in-memory registry
        modelLock.lock()
        let models = Array(registeredModels.values)
        modelLock.unlock()

        // Apply basic filtering (full implementation moved to modular components)
        return models.filter { model in
            if let framework = criteria.framework {
                return model.compatibleFrameworks.contains(framework)
            }
            if let format = criteria.format {
                return model.format == format
            }
            return true
        }
    }

    // Compatibility detection moved to modular components

    // MARK: - Helper Methods

    private func setupDefaultProviders() {
        // SDK doesn't include providers by default
        // They should be registered by the app
    }
}

// Local storage functionality moved to modular RegistryStorage component
