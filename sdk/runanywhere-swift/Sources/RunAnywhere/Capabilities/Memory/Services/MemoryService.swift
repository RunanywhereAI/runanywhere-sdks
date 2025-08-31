import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Central memory management service
class MemoryService: MemoryManager {
    private let allocationManager: AllocationManager
    private let pressureHandler: PressureHandler
    private let cacheEviction: CacheEviction
    private let memoryMonitor: MemoryMonitor
    private let logger: SDKLogger = SDKLogger(category: "MemoryService")

    init(
        allocationManager: AllocationManager = AllocationManager(),
        pressureHandler: PressureHandler = PressureHandler(),
        cacheEviction: CacheEviction = CacheEviction(),
        memoryMonitor: MemoryMonitor = MemoryMonitor()
    ) {
        self.allocationManager = allocationManager
        self.pressureHandler = pressureHandler
        self.cacheEviction = cacheEviction
        self.memoryMonitor = memoryMonitor

        setupIntegration()
    }

    /// Configuration for memory service
    struct Config {
        var memoryThreshold: Int64 = 500_000_000 // 500MB
        var criticalThreshold: Int64 = 200_000_000 // 200MB
        var monitoringInterval: TimeInterval = 5.0
        var unloadStrategy: UnloadStrategy = .leastRecentlyUsed

        enum UnloadStrategy {
            case leastRecentlyUsed
            case largestFirst
            case oldestFirst
            case priorityBased
        }
    }

    private var config: Config = Config()

    func configure(_ config: Config) {
        self.config = config
        allocationManager.configure(config)
        pressureHandler.configure(config)
        cacheEviction.configure(config)
        memoryMonitor.configure(config)
    }

    // MARK: - Model Memory Management

    func registerModel(_ model: MemoryLoadedModel, size: Int64, service: LLMService, priority: MemoryPriority = .normal) {
        allocationManager.registerModel(model, size: size, service: service, priority: priority)

        // Check for memory pressure after registration
        Task {
            await checkMemoryConditions()
        }
    }

    func unregisterModel(_ modelId: String) {
        allocationManager.unregisterModel(modelId)
    }

    func touchModel(_ modelId: String) {
        allocationManager.touchModel(modelId)
    }

    // MARK: - Memory Pressure Management

    func handleMemoryPressure(level: MemoryPressureLevel = .warning) async {
        logger.info("Handling memory pressure at level: \(level)")

        let targetMemory = calculateTargetMemory(for: level)
        let modelsToEvict = cacheEviction.selectModelsToEvict(targetMemory: targetMemory)

        await pressureHandler.handlePressure(level: level, modelsToEvict: modelsToEvict)
    }

    func requestMemory(size: Int64, priority: MemoryPriority = .normal) async -> Bool {
        return await allocationManager.requestMemory(size: size, priority: priority)
    }

    func releaseMemory(size: Int64) async {
        await allocationManager.releaseMemory(size: size)
    }

    // MARK: - MemoryManager Protocol

    func registerLoadedModel(_ model: LoadedModel, size: Int64, service: LLMService) {
        let framework = service.modelInfo?.framework ?? model.model.preferredFramework ?? .coreML
        let memoryModel = MemoryLoadedModel(
            id: model.model.id,
            name: model.model.name,
            size: size,
            framework: framework
        )
        registerModel(memoryModel, size: size, service: service)
    }

    func getCurrentMemoryUsage() -> Int64 {
        return allocationManager.getTotalModelMemory()
    }

    func getAvailableMemory() -> Int64 {
        return memoryMonitor.getAvailableMemory()
    }

    func hasAvailableMemory(for size: Int64) -> Bool {
        return getAvailableMemory() >= size
    }

    func canAllocate(_ size: Int64) async throws -> Bool {
        return await requestMemory(size: size)
    }

    func handleMemoryPressure() async {
        await handleMemoryPressure(level: .warning)
    }

    func setMemoryThreshold(_ threshold: Int64) {
        config.memoryThreshold = threshold
    }

    func getLoadedModels() -> [LoadedModel] {
        let memoryModels = allocationManager.getLoadedModels()
        return memoryModels
            .filter { $0.service != nil }
            .map { memModelInfo in
                let service = memModelInfo.service!

                // Create a ModelInfo from the MemoryLoadedModel
                let modelInfo = ModelInfo(
                    id: memModelInfo.model.id,
                    name: memModelInfo.model.name,
                    category: .language, // Default category - ideally this should be determined from the model
                    format: .gguf, // Default format - ideally this should be stored in MemoryLoadedModel
                    compatibleFrameworks: [memModelInfo.model.framework]
                )

                return LoadedModel(model: modelInfo, service: service)
            }
    }

    func isHealthy() -> Bool {
        // Basic health check - ensure all components are available
        return memoryMonitor.getAvailableMemory() > 0
    }

    // MARK: - Memory Information

    func getMemoryStatistics() -> MemoryStatistics {
        let totalMemory = memoryMonitor.getTotalMemory()
        let availableMemory = memoryMonitor.getAvailableMemory()
        let modelMemory = allocationManager.getTotalModelMemory()
        let loadedModelCount = allocationManager.getLoadedModelCount()
        let memoryPressure = availableMemory < config.memoryThreshold

        return MemoryStatistics(
            totalMemory: totalMemory,
            availableMemory: availableMemory,
            modelMemory: modelMemory,
            loadedModelCount: loadedModelCount,
            memoryPressure: memoryPressure
        )
    }

    func isModelLoaded(_ modelId: String) -> Bool {
        return allocationManager.isModelLoaded(modelId)
    }

    func getModelMemoryUsage(_ modelId: String) -> Int64? {
        return allocationManager.getModelMemoryUsage(modelId)
    }

    func getLoadedModels() -> [MemoryLoadedModelInfo] {
        return allocationManager.getLoadedModels()
    }

    // MARK: - Memory Monitoring

    func startMonitoring() {
        memoryMonitor.startMonitoring { [weak self] stats in
            Task {
                await self?.handleMonitoringUpdate(stats)
            }
        }
    }

    func stopMonitoring() {
        memoryMonitor.stopMonitoring()
    }

    // MARK: - Private Implementation

    private func setupIntegration() {
        // Connect pressure handler with cache eviction
        pressureHandler.setEvictionHandler(cacheEviction)

        // Connect allocation manager with pressure monitoring
        allocationManager.setPressureCallback { [weak self] in
            Task {
                await self?.checkMemoryConditions()
            }
        }
    }

    private func checkMemoryConditions() async {
        let availableMemory = memoryMonitor.getAvailableMemory()

        if availableMemory < config.criticalThreshold {
            await handleMemoryPressure(level: .critical)
        } else if availableMemory < config.memoryThreshold {
            await handleMemoryPressure(level: .warning)
        }
    }

    private func calculateTargetMemory(for level: MemoryPressureLevel) -> Int64 {
        switch level {
        case .low, .medium:
            return config.memoryThreshold
        case .high:
            return Int64(Double(config.memoryThreshold) * 1.5)
        case .warning:
            return config.memoryThreshold * 2
        case .critical:
            return config.memoryThreshold * 3
        }
    }

    private func handleMonitoringUpdate(_ stats: MemoryMonitoringStats) async {
        if stats.availableMemory < config.criticalThreshold {
            await handleMemoryPressure(level: .critical)
        } else if stats.availableMemory < config.memoryThreshold {
            await handleMemoryPressure(level: .warning)
        }
    }
}


/// Memory statistics
struct MemoryStatistics {
    let totalMemory: Int64
    let availableMemory: Int64
    let modelMemory: Int64
    let loadedModelCount: Int
    let memoryPressure: Bool

    var usedMemoryPercentage: Double {
        let used = totalMemory - availableMemory
        return Double(used) / Double(totalMemory) * 100
    }

    var modelMemoryPercentage: Double {
        Double(modelMemory) / Double(totalMemory) * 100
    }
}
