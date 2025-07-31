import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Unified memory management system with coordinated cleanup and pressure handling
public class UnifiedMemoryManager {
    public static let shared = UnifiedMemoryManager()
    
    private var loadedModels: [String: LoadedModelInfo] = [:]
    private var memoryPressureObserver: NSObjectProtocol?
    private let modelLock = NSLock()
    private var memoryMonitorTimer: Timer?
    
    /// Configuration for memory management
    public struct MemoryConfig {
        public var memoryThreshold: Int64 = 500_000_000 // 500MB
        public var criticalThreshold: Int64 = 200_000_000 // 200MB
        public var monitoringInterval: TimeInterval = 5.0
        public var unloadStrategy: UnloadStrategy = .leastRecentlyUsed
        
        public init() {}
    }
    
    /// Strategy for unloading models
    public enum UnloadStrategy {
        case leastRecentlyUsed
        case largestFirst
        case oldestFirst
        case priorityBased
    }
    
    /// Information about a loaded model
    public struct LoadedModelInfo {
        public let model: LoadedModel
        public let size: Int64
        public var lastUsed: Date
        public weak var service: LLMService?
        public let priority: ModelPriority
        
        public init(
            model: LoadedModel,
            size: Int64,
            lastUsed: Date = Date(),
            service: LLMService? = nil,
            priority: ModelPriority = .normal
        ) {
            self.model = model
            self.size = size
            self.lastUsed = lastUsed
            self.service = service
            self.priority = priority
        }
    }
    
    /// Model priority for memory management
    public enum ModelPriority: Int {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3 // Never unload unless absolutely necessary
    }
    
    /// Loaded model information
    public struct LoadedModel {
        public let id: String
        public let name: String
        public let framework: LLMFramework
        public let modelPath: URL
        
        public init(id: String, name: String, framework: LLMFramework, modelPath: URL) {
            self.id = id
            self.name = name
            self.framework = framework
            self.modelPath = modelPath
        }
    }
    
    private var config = MemoryConfig()
    
    private init() {
        setupMemoryPressureHandling()
        startMemoryMonitoring()
    }
    
    deinit {
        stopMemoryMonitoring()
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Configure memory manager
    public func configure(_ config: MemoryConfig) {
        self.config = config
        stopMemoryMonitoring()
        startMemoryMonitoring()
    }
    
    // MARK: - Model Registration
    
    /// Register a loaded model
    public func registerLoadedModel(
        _ model: LoadedModel,
        size: Int64,
        service: LLMService,
        priority: ModelPriority = .normal
    ) {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        loadedModels[model.id] = LoadedModelInfo(
            model: model,
            size: size,
            service: service,
            priority: priority
        )
        
        // Check memory after loading
        Task {
            await checkMemoryUsage()
        }
    }
    
    /// Update last used time for a model
    public func touchModel(_ modelId: String) {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        if var modelInfo = loadedModels[modelId] {
            modelInfo.lastUsed = Date()
            loadedModels[modelId] = modelInfo
        }
    }
    
    /// Unregister a model
    public func unregisterModel(_ modelId: String) {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        loadedModels.removeValue(forKey: modelId)
    }
    
    // MARK: - Memory Monitoring
    
    private func setupMemoryPressureHandling() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryPressure(level: .critical)
            }
        }
        #elseif os(macOS)
        // macOS doesn't have system memory warnings, rely on manual monitoring
        #endif
    }
    
    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: config.monitoringInterval,
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.checkMemoryUsage()
            }
        }
    }
    
    private func stopMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }
    
    /// Check current memory usage
    public func checkMemoryUsage() async {
        let availableMemory = getAvailableMemory()
        let usedMemory = getTotalModelMemory()
        
        if availableMemory < config.criticalThreshold {
            await handleMemoryPressure(level: .critical)
        } else if availableMemory < config.memoryThreshold {
            await handleMemoryPressure(level: .warning)
        }
        
        // Log memory status
        print("[MemoryManager] Available: \(ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory)), Used by models: \(ByteCountFormatter.string(fromByteCount: usedMemory, countStyle: .memory))")
    }
    
    /// Memory pressure levels
    public enum MemoryPressureLevel {
        case warning
        case critical
    }
    
    /// Handle memory pressure
    public func handleMemoryPressure(level: MemoryPressureLevel = .warning) async {
        let targetMemory: Int64
        switch level {
        case .warning:
            targetMemory = config.memoryThreshold * 2
        case .critical:
            targetMemory = config.memoryThreshold * 3
        }
        
        let modelsToUnload = selectModelsToUnload(targetMemory: targetMemory)
        
        for modelId in modelsToUnload {
            await unloadModel(modelId)
            
            // Check if we've freed enough memory
            if getAvailableMemory() > targetMemory {
                break
            }
        }
    }
    
    // MARK: - Model Selection for Unloading
    
    private func selectModelsToUnload(targetMemory: Int64) -> [String] {
        modelLock.lock()
        let models = Array(loadedModels.values)
        modelLock.unlock()
        
        var sortedModels: [LoadedModelInfo]
        
        switch config.unloadStrategy {
        case .leastRecentlyUsed:
            sortedModels = models.sorted { $0.lastUsed < $1.lastUsed }
            
        case .largestFirst:
            sortedModels = models.sorted { $0.size > $1.size }
            
        case .oldestFirst:
            sortedModels = models.sorted { $0.lastUsed < $1.lastUsed }
            
        case .priorityBased:
            sortedModels = models.sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority.rawValue < rhs.priority.rawValue
                }
                return lhs.lastUsed < rhs.lastUsed
            }
        }
        
        var modelsToUnload: [String] = []
        var freedMemory: Int64 = 0
        let currentAvailable = getAvailableMemory()
        let neededMemory = targetMemory - currentAvailable
        
        for model in sortedModels {
            // Skip critical priority models unless absolutely necessary
            if model.priority == .critical && currentAvailable + freedMemory > config.criticalThreshold {
                continue
            }
            
            modelsToUnload.append(model.model.id)
            freedMemory += model.size
            
            if freedMemory >= neededMemory {
                break
            }
        }
        
        return modelsToUnload
    }
    
    // MARK: - Model Unloading
    
    /// Unload a specific model
    public func unloadModel(_ modelId: String) async {
        modelLock.lock()
        guard let modelInfo = loadedModels[modelId] else {
            modelLock.unlock()
            return
        }
        modelLock.unlock()
        
        print("[MemoryManager] Unloading model: \(modelInfo.model.name) to free \(ByteCountFormatter.string(fromByteCount: modelInfo.size, countStyle: .memory))")
        
        // Notify service to cleanup
        await modelInfo.service?.cleanup()
        
        // Remove from tracking
        modelLock.lock()
        loadedModels.removeValue(forKey: modelId)
        modelLock.unlock()
        
        // Force memory reclaim
        autoreleasepool {
            // Trigger cleanup
        }
    }
    
    /// Unload all models with a specific priority or lower
    public func unloadModelsByPriority(_ maxPriority: ModelPriority) async {
        modelLock.lock()
        let modelsToUnload = loadedModels.values
            .filter { $0.priority.rawValue <= maxPriority.rawValue }
            .map { $0.model.id }
        modelLock.unlock()
        
        for modelId in modelsToUnload {
            await unloadModel(modelId)
        }
    }
    
    // MARK: - Memory Information
    
    /// Get total memory used by loaded models
    public func getTotalModelMemory() -> Int64 {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        return loadedModels.values.reduce(0) { $0 + $1.size }
    }
    
    /// Get information about loaded models
    public func getLoadedModels() -> [LoadedModelInfo] {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        return Array(loadedModels.values)
    }
    
    /// Check if a model is loaded
    public func isModelLoaded(_ modelId: String) -> Bool {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        return loadedModels[modelId] != nil
    }
    
    /// Get memory usage for a specific model
    public func getModelMemoryUsage(_ modelId: String) -> Int64? {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        return loadedModels[modelId]?.size
    }
    
    // MARK: - System Memory Information
    
    /// Get available system memory
    public func getAvailableMemory() -> Int64 {
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
    
    /// Get total system memory
    public func getTotalMemory() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }
    
    /// Get memory statistics
    public func getMemoryStatistics() -> MemoryStatistics {
        return MemoryStatistics(
            totalMemory: getTotalMemory(),
            availableMemory: getAvailableMemory(),
            modelMemory: getTotalModelMemory(),
            loadedModelCount: loadedModels.count,
            memoryPressure: getAvailableMemory() < config.memoryThreshold
        )
    }
    
    /// Memory statistics
    public struct MemoryStatistics {
        public let totalMemory: Int64
        public let availableMemory: Int64
        public let modelMemory: Int64
        public let loadedModelCount: Int
        public let memoryPressure: Bool
        
        public var usedMemoryPercentage: Double {
            let used = totalMemory - availableMemory
            return Double(used) / Double(totalMemory) * 100
        }
        
        public var modelMemoryPercentage: Double {
            return Double(modelMemory) / Double(totalMemory) * 100
        }
    }
}

// MARK: - Memory Manager Protocol Extension

extension UnifiedMemoryManager: MemoryManager {
    public func checkAvailableMemory() async -> Int64 {
        return getAvailableMemory()
    }
    
    public func requestMemory(size: Int64) async throws -> Bool {
        let available = getAvailableMemory()
        
        if available >= size {
            return true
        }
        
        // Try to free memory
        await handleMemoryPressure(level: .warning)
        
        // Check again
        let newAvailable = getAvailableMemory()
        return newAvailable >= size
    }
    
    public func releaseMemory(size: Int64) async {
        // Memory is automatically released when models are unloaded
        // This is a no-op for now but could track memory allocations in the future
    }
}