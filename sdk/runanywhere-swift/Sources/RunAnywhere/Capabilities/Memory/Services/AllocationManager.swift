import Foundation

/// Manages memory allocation and model registration
class AllocationManager {
    private var loadedModels: [String: MemoryLoadedModelInfo] = [:]
    private let modelLock = UnfairLock()
    private var pressureCallback: (() -> Void)?
    private let logger: SDKLogger = SDKLogger(category: "AllocationManager")

    func setPressureCallback(_ callback: @escaping () -> Void) {
        pressureCallback = callback
    }

    // MARK: - Model Registration

    func registerModel(_ model: MemoryLoadedModel, size: Int64, service: LLMService, priority: MemoryPriority = .normal) {
        modelLock.withLock {
            let modelInfo = MemoryLoadedModelInfo(
                model: model,
                size: size,
                service: service,
                priority: priority
            )

            loadedModels[model.id] = modelInfo

            logger.info("Registered model '\(model.name)' with \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")

            // Trigger pressure check
            pressureCallback?()
        }
    }

    func unregisterModel(_ modelId: String) {
        modelLock.withLock {
            if let modelInfo = loadedModels.removeValue(forKey: modelId) {
                logger.info("Unregistered model '\(modelInfo.model.name)'")
            }
        }
    }

    func touchModel(_ modelId: String) {
        modelLock.withLock {
            if var modelInfo = loadedModels[modelId] {
                modelInfo.lastUsed = Date()
                loadedModels[modelId] = modelInfo
            }
        }
    }

    // MARK: - Memory Requests

    func requestMemory(size: Int64, priority: MemoryPriority = .normal) async -> Bool {
        let availableMemory = getCurrentAvailableMemory()

        if availableMemory >= size {
            logger.debug("Memory request granted: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")
            return true
        }

        logger.info("Insufficient memory, attempting to free space for \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")

        // Try to free memory based on priority
        let needed = size - availableMemory
        let freed = await freeMemory(needed: needed, requesterPriority: priority)

        let newAvailable = getCurrentAvailableMemory()
        let success = newAvailable >= size

        if success {
            logger.info("Memory request successful after freeing \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .memory))")
        } else {
            logger.warning("Memory request failed, insufficient memory available")
        }

        return success
    }

    func releaseMemory(size: Int64) async {
        // Memory is automatically released when models are unloaded
        // This tracks explicit memory releases for accounting
        logger.debug("Released \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")
    }

    // MARK: - Memory Information

    func getTotalModelMemory() -> Int64 {
        return modelLock.withLock {
            return loadedModels.values.reduce(0) { $0 + $1.size }
        }
    }

    func getLoadedModelCount() -> Int {
        return modelLock.withLock {
            return loadedModels.count
        }
    }

    func getLoadedModels() -> [MemoryLoadedModelInfo] {
        return modelLock.withLock {
            return Array(loadedModels.values)
        }
    }

    func isModelLoaded(_ modelId: String) -> Bool {
        return modelLock.withLock {
            return loadedModels[modelId] != nil
        }
    }

    func getModelMemoryUsage(_ modelId: String) -> Int64? {
        return modelLock.withLock {
            return loadedModels[modelId]?.size
        }
    }

    func getModelsForEviction() -> [MemoryLoadedModelInfo] {
        return modelLock.withLock {
            return Array(loadedModels.values)
        }
    }

    // MARK: - Model Unloading

    func unloadModel(_ modelId: String) async -> Int64 {
        let modelInfo = modelLock.withLock { () -> MemoryLoadedModelInfo? in
            guard let info = loadedModels[modelId] else {
                return nil
            }
            loadedModels.removeValue(forKey: modelId)
            return info
        }

        guard let modelInfo = modelInfo else {
            return 0
        }

        let size = modelInfo.size
        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .memory)
        logger.info("Unloading model '\(modelInfo.model.name)' to free \(sizeString)")

        // Notify service to cleanup
        await modelInfo.service?.cleanup()

        // Force memory reclaim
        autoreleasepool {
            // Trigger cleanup
        }

        return size
    }

    func unloadModels(_ modelIds: [String]) async -> Int64 {
        var totalFreed: Int64 = 0

        for modelId in modelIds {
            totalFreed += await unloadModel(modelId)
        }

        return totalFreed
    }

    // MARK: - Private Implementation

    private func getCurrentAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = info.resident_size
            return Int64(totalMemory) - Int64(usedMemory)
        }

        // Fallback to process info
        return Int64(ProcessInfo.processInfo.physicalMemory / 2) // Assume 50% available
    }

    private func freeMemory(needed: Int64, requesterPriority: MemoryPriority) async -> Int64 {
        let models = modelLock.withLock {
            return Array(loadedModels.values)
        }

        // Sort models by eviction priority
        let sortedModels = models.sorted { lhs, rhs in
            // Higher priority models are less likely to be evicted
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }
            // If same priority, evict least recently used first
            return lhs.lastUsed < rhs.lastUsed
        }

        var freedMemory: Int64 = 0
        var modelsToUnload: [String] = []

        for model in sortedModels {
            // Don't evict models with higher or equal priority unless absolutely necessary
            if model.priority.rawValue >= requesterPriority.rawValue && freedMemory > 0 {
                continue
            }

            modelsToUnload.append(model.model.id)
            freedMemory += model.size

            if freedMemory >= needed {
                break
            }
        }

        // Unload selected models
        let actualFreed = await unloadModels(modelsToUnload)
        return actualFreed
    }
}
