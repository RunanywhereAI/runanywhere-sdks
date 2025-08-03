import Foundation

/// In-memory cache for registry operations
class RegistryCache {
    private var cache: [String: ModelInfo] = [:]
    private let cacheQueue = DispatchQueue(label: "registry.cache", attributes: .concurrent)
    private var lastCacheUpdate: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes

    func get(_ modelId: String) -> ModelInfo? {
        return cacheQueue.sync {
            cache[modelId]
        }
    }

    func set(_ model: ModelInfo) {
        cacheQueue.async(flags: .barrier) {
            self.cache[model.id] = model
            self.lastCacheUpdate = Date()
        }
    }

    func remove(_ modelId: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: modelId)
            self.lastCacheUpdate = Date()
        }
    }

    func getAll() -> [ModelInfo] {
        return cacheQueue.sync {
            Array(cache.values)
        }
    }

    func clear() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.lastCacheUpdate = Date()
        }
    }

    func isCacheValid() -> Bool {
        guard let lastUpdate = lastCacheUpdate else {
            return false
        }
        return Date().timeIntervalSince(lastUpdate) < cacheTimeout
    }

    func getCacheInfo() -> CacheInfo {
        return cacheQueue.sync {
            CacheInfo(
                itemCount: cache.count,
                lastUpdate: lastCacheUpdate,
                isValid: isCacheValid()
            )
        }
    }

    func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        return cacheQueue.sync {
            let models = Array(cache.values)
            return models.filter { model in
                // Framework filter
                if let framework = criteria.framework {
                    guard model.compatibleFrameworks.contains(framework) else {
                        return false
                    }
                }

                // Format filter
                if let format = criteria.format {
                    guard model.format == format else {
                        return false
                    }
                }

                // Size filter
                if let maxSize = criteria.maxSize {
                    guard model.estimatedMemory <= maxSize else {
                        return false
                    }
                }

                return true
            }
        }
    }
}

/// Information about cache state
struct CacheInfo {
    let itemCount: Int
    let lastUpdate: Date?
    let isValid: Bool
}
