import Foundation

/// Service responsible for updating registry with discovered models
class RegistryUpdater {
    private let discovery: ModelDiscovery
    private let storage: RegistryStorage
    private var config: DiscoveryConfig = DiscoveryConfig()
    private var lastDiscovery: Date?
    private var discoveryCache: [ModelInfo] = []

    init(
        discovery: ModelDiscovery = ModelDiscovery(),
        storage: RegistryStorage = RegistryStorage()
    ) {
        self.discovery = discovery
        self.storage = storage
    }

    func configure(_ config: DiscoveryConfig) {
        self.config = config
    }

    func updateRegistry() async -> [ModelInfo] {
        // Check cache
        if let lastDiscovery = lastDiscovery,
           Date().timeIntervalSince(lastDiscovery) < config.cacheTimeout {
            return discoveryCache
        }

        var allModels: [ModelInfo] = []

        // Discover local models
        if config.includeLocalModels {
            let localModels = await discovery.discoverLocalModels()
            allModels.append(contentsOf: localModels)
        }

        // Discover online models
        if config.includeOnlineModels {
            let onlineModels = await discovery.discoverOnlineModels()
            allModels.append(contentsOf: onlineModels)
        }

        // Deduplicate by ID
        let uniqueModels = deduplicateModels(allModels)

        // Save to storage
        for model in uniqueModels {
            await storage.saveModel(model)
        }

        // Update cache
        discoveryCache = uniqueModels
        lastDiscovery = Date()

        return uniqueModels
    }

    func registerProvider(_ provider: ModelProvider) {
        discovery.registerProvider(provider)
    }

    private func deduplicateModels(_ models: [ModelInfo]) -> [ModelInfo] {
        var seen = Set<String>()
        var unique: [ModelInfo] = []

        for model in models {
            if !seen.contains(model.id) {
                seen.insert(model.id)
                unique.append(model)
            }
        }

        return unique
    }
}

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
