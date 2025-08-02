import Foundation

/// Manages cache eviction strategies and model selection for memory cleanup
class CacheEviction {
    private let logger = SDKLogger(category: "CacheEviction")
    private var config = MemoryService.Config()

    func configure(_ config: MemoryService.Config) {
        self.config = config
    }

    // MARK: - Model Selection for Eviction

    func selectModelsToEvict(targetMemory: Int64) -> [String] {
        // Get current models from allocation manager (would be injected in real implementation)
        let models = getCurrentModels()

        return selectModelsUsingStrategy(models: models, targetMemory: targetMemory, aggressive: false)
    }

    func selectModelsForCriticalEviction(targetMemory: Int64) -> [String] {
        let models = getCurrentModels()

        return selectModelsUsingStrategy(models: models, targetMemory: targetMemory, aggressive: true)
    }

    func selectModelsToEvict(count: Int) -> [String] {
        let models = getCurrentModels()
        let sortedModels = sortModelsByEvictionPriority(models, aggressive: false)

        return Array(sortedModels.prefix(count)).map { $0.model.id }
    }

    func selectLeastImportantModels(maxCount: Int) -> [String] {
        let models = getCurrentModels()
        let sortedModels = sortModelsByImportance(models)

        return Array(sortedModels.prefix(maxCount)).map { $0.model.id }
    }

    // MARK: - Eviction Strategies

    private func selectModelsUsingStrategy(models: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        switch config.unloadStrategy {
        case .leastRecentlyUsed:
            return selectByLeastRecentlyUsed(models: models, targetMemory: targetMemory, aggressive: aggressive)
        case .largestFirst:
            return selectByLargestFirst(models: models, targetMemory: targetMemory, aggressive: aggressive)
        case .oldestFirst:
            return selectByOldestFirst(models: models, targetMemory: targetMemory, aggressive: aggressive)
        case .priorityBased:
            return selectByPriority(models: models, targetMemory: targetMemory, aggressive: aggressive)
        }
    }

    private func selectByLeastRecentlyUsed(models: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        let sortedModels = models.sorted { $0.lastUsed < $1.lastUsed }
        return selectModelsToTarget(sortedModels: sortedModels, targetMemory: targetMemory, aggressive: aggressive)
    }

    private func selectByLargestFirst(models: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        let sortedModels = models.sorted { $0.size > $1.size }
        return selectModelsToTarget(sortedModels: sortedModels, targetMemory: targetMemory, aggressive: aggressive)
    }

    private func selectByOldestFirst(models: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        let sortedModels = models.sorted { $0.lastUsed < $1.lastUsed }
        return selectModelsToTarget(sortedModels: sortedModels, targetMemory: targetMemory, aggressive: aggressive)
    }

    private func selectByPriority(models: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        let sortedModels = models.sorted { lhs, rhs in
            // Lower priority models are evicted first
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }
            // If same priority, evict least recently used first
            return lhs.lastUsed < rhs.lastUsed
        }
        return selectModelsToTarget(sortedModels: sortedModels, targetMemory: targetMemory, aggressive: aggressive)
    }

    private func selectModelsToTarget(sortedModels: [LoadedModelInfo], targetMemory: Int64, aggressive: Bool) -> [String] {
        var modelsToEvict: [String] = []
        var freedMemory: Int64 = 0

        for model in sortedModels {
            // In non-aggressive mode, skip critical priority models unless absolutely necessary
            if !aggressive && model.priority == .critical && freedMemory > 0 {
                continue
            }

            modelsToEvict.append(model.model.id)
            freedMemory += model.size

            logger.debug("Selected model '\(model.model.name)' for eviction (size: \(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .memory)))")

            if freedMemory >= targetMemory {
                break
            }
        }

        logger.info("Selected \(modelsToEvict.count) models for eviction, target memory: \(ByteCountFormatter.string(fromByteCount: targetMemory, countStyle: .memory))")

        return modelsToEvict
    }

    // MARK: - Model Sorting

    private func sortModelsByEvictionPriority(_ models: [LoadedModelInfo], aggressive: Bool) -> [LoadedModelInfo] {
        return models.sorted { lhs, rhs in
            // In aggressive mode, ignore critical priority
            if !aggressive {
                if lhs.priority != rhs.priority {
                    return lhs.priority.rawValue < rhs.priority.rawValue
                }
            }

            // Consider both recency and size
            let lhsScore = calculateEvictionScore(model: lhs)
            let rhsScore = calculateEvictionScore(model: rhs)

            return lhsScore < rhsScore // Lower score = higher eviction priority
        }
    }

    private func sortModelsByImportance(_ models: [LoadedModelInfo]) -> [LoadedModelInfo] {
        return models.sorted { lhs, rhs in
            // Higher priority = more important (lower eviction priority)
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }

            // More recently used = more important
            return lhs.lastUsed < rhs.lastUsed
        }
    }

    private func calculateEvictionScore(model: LoadedModelInfo) -> Double {
        let timeSinceUse = Date().timeIntervalSince(model.lastUsed)
        let priorityWeight = Double(model.priority.rawValue) * 1000 // Higher priority = higher score
        let recencyScore = timeSinceUse / 3600 // Hours since last use

        // Lower score = higher eviction priority
        return priorityWeight - recencyScore
    }

    // MARK: - Model Information

    func getEvictionCandidates(minMemory: Int64) -> [LoadedModelInfo] {
        let models = getCurrentModels()
        return models.filter { $0.size >= minMemory }
    }

    func getModelsByPriority(_ priority: MemoryPriority) -> [LoadedModelInfo] {
        let models = getCurrentModels()
        return models.filter { $0.priority == priority }
    }

    func getModelsByUsageAge(olderThan interval: TimeInterval) -> [LoadedModelInfo] {
        let models = getCurrentModels()
        let cutoffDate = Date().addingTimeInterval(-interval)
        return models.filter { $0.lastUsed < cutoffDate }
    }

    // MARK: - Statistics

    func getEvictionStatistics() -> EvictionStatistics {
        let models = getCurrentModels()

        let totalMemory = models.reduce(0) { $0 + $1.size }
        let modelsByPriority = Dictionary(grouping: models) { $0.priority }

        let avgLastUsed = models.isEmpty ? Date() :
            Date(timeIntervalSince1970: models.map { $0.lastUsed.timeIntervalSince1970 }.reduce(0, +) / Double(models.count))

        return EvictionStatistics(
            totalModels: models.count,
            totalMemory: totalMemory,
            modelsByPriority: modelsByPriority.mapValues { $0.count },
            averageLastUsed: avgLastUsed,
            oldestModel: models.min { $0.lastUsed < $1.lastUsed }?.lastUsed ?? Date(),
            largestModel: models.max { $0.size < $1.size }?.size ?? 0
        )
    }

    // MARK: - Private Implementation

    private func getCurrentModels() -> [LoadedModelInfo] {
        // In real implementation, this would get models from AllocationManager
        // For now, return empty array
        return []
    }
}

/// Statistics about eviction state
struct EvictionStatistics {
    let totalModels: Int
    let totalMemory: Int64
    let modelsByPriority: [MemoryPriority: Int]
    let averageLastUsed: Date
    let oldestModel: Date
    let largestModel: Int64

    var totalMemoryString: String {
        ByteCountFormatter.string(fromByteCount: totalMemory, countStyle: .memory)
    }

    var largestModelString: String {
        ByteCountFormatter.string(fromByteCount: largestModel, countStyle: .memory)
    }
}
