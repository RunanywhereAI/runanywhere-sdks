import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Handles memory pressure situations and coordinates response actions
class PressureHandler {
    private let logger: SDKLogger = SDKLogger(category: "PressureHandler")
    private var evictionHandler: CacheEviction?
    private var memoryPressureObserver: NSObjectProtocol?
    private var config: MemoryService.Config = MemoryService.Config()

    init() {
        setupSystemPressureHandling()
    }

    deinit {
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func configure(_ config: MemoryService.Config) {
        self.config = config
    }

    func setEvictionHandler(_ handler: CacheEviction) {
        evictionHandler = handler
    }

    // MARK: - Pressure Handling

    func handlePressure(level: MemoryPressureLevel, modelsToEvict: [String] = []) async {
        logger.info("Handling memory pressure at level: \(level)")

        let startTime = Date()
        var totalFreed: Int64 = 0

        switch level {
        case .low, .medium:
            // No action needed for low/medium pressure
            totalFreed = 0
        case .high:
            // Light cleanup for high pressure
            totalFreed = await handleWarningPressure(modelsToEvict: modelsToEvict)
        case .warning:
            totalFreed = await handleWarningPressure(modelsToEvict: modelsToEvict)
        case .critical:
            totalFreed = await handleCriticalPressure(modelsToEvict: modelsToEvict)
        }

        let duration = Date().timeIntervalSince(startTime)
        let freedString = ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .memory)

        logger.info("Memory pressure handling completed in \(String(format: "%.2f", duration))s, freed \(freedString)")

        // Post pressure handling notification
        postPressureHandlingNotification(level: level, freedMemory: totalFreed, duration: duration)
    }

    func handleSystemMemoryWarning() async {
        logger.warning("System memory warning received")
        await handlePressure(level: .critical)
    }

    // MARK: - Pressure Response Strategies

    private func handleWarningPressure(modelsToEvict: [String]) async -> Int64 {
        var totalFreed: Int64 = 0

        // First, try evicting suggested models
        if !modelsToEvict.isEmpty {
            totalFreed += await evictModels(modelsToEvict)
        }

        // If that's not enough, use eviction handler to find more candidates
        if totalFreed < calculateTargetFreedMemory(for: .warning) {
            guard let evictionHandler = evictionHandler else {
                logger.error("No eviction handler available for additional cleanup")
                return totalFreed
            }

            let additionalTarget = calculateTargetFreedMemory(for: .warning) - totalFreed
            let additionalModels = evictionHandler.selectModelsToEvict(targetMemory: additionalTarget)
            totalFreed += await evictModels(additionalModels)
        }

        return totalFreed
    }

    private func handleCriticalPressure(modelsToEvict: [String]) async -> Int64 {
        var totalFreed: Int64 = 0

        // In critical situations, be more aggressive
        if !modelsToEvict.isEmpty {
            totalFreed += await evictModels(modelsToEvict)
        }

        // Force additional cleanup if needed
        if totalFreed < calculateTargetFreedMemory(for: .critical) {
            guard let evictionHandler = evictionHandler else {
                logger.error("No eviction handler available for critical cleanup")
                return totalFreed
            }

            // Use more aggressive eviction strategy
            let additionalTarget = calculateTargetFreedMemory(for: .critical) - totalFreed
            let additionalModels = evictionHandler.selectModelsForCriticalEviction(targetMemory: additionalTarget)
            totalFreed += await evictModels(additionalModels)
        }

        // Force garbage collection
        performSystemCleanup()

        return totalFreed
    }

    // MARK: - Memory Eviction

    private func evictModels(_ modelIds: [String]) async -> Int64 {
        guard !modelIds.isEmpty else { return 0 }

        logger.info("Evicting \(modelIds.count) models due to memory pressure")

        var totalFreed: Int64 = 0
        for modelId in modelIds {
            totalFreed += await evictModel(modelId)
        }

        return totalFreed
    }

    private func evictModel(_ modelId: String) async -> Int64 {
        // This would normally delegate to the allocation manager
        // For now, return a placeholder value
        logger.debug("Evicting model: \(modelId)")
        return 0 // Will be implemented when integrated with AllocationManager
    }

    // MARK: - System Integration

    private func setupSystemPressureHandling() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleSystemMemoryWarning()
            }
        }
        #elseif os(macOS)
        // macOS doesn't have system memory warnings, rely on manual monitoring
        #endif
    }

    private func performSystemCleanup() {
        // Force autorelease pool cleanup
        autoreleasepool {
            // This helps release any autoreleased objects
        }

        // Suggest garbage collection (not guaranteed)
        #if DEBUG
        // In debug builds, we can be more aggressive
        #endif
    }

    // MARK: - Memory Calculations

    private func calculateTargetFreedMemory(for level: MemoryPressureLevel) -> Int64 {
        switch level {
        case .low, .medium:
            return 0
        case .high:
            return config.memoryThreshold / 2
        case .warning:
            return config.memoryThreshold
        case .critical:
            return config.memoryThreshold * 2
        }
    }

    // MARK: - Notifications

    private func postPressureHandlingNotification(level: MemoryPressureLevel, freedMemory: Int64, duration: TimeInterval) {
        let response = MemoryPressureNotificationInfo(
            level: level,
            freedMemory: freedMemory,
            duration: duration
        )

        let userInfo: [String: Any] = [
            "response": response
        ]

        NotificationCenter.default.post(
            name: .memoryPressureHandled,
            object: self,
            userInfo: userInfo
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let memoryPressureHandled: Notification.Name = Notification.Name("MemoryPressureHandled")
}

// MARK: - Memory Pressure Response

/// Information about memory pressure notification
struct MemoryPressureNotificationInfo: Sendable {
    let level: MemoryPressureLevel
    let freedMemory: Int64
    let duration: TimeInterval

    var freedMemoryString: String {
        ByteCountFormatter.string(fromByteCount: freedMemory, countStyle: .memory)
    }
}

/// Information about memory pressure response
struct MemoryPressureResponse: Sendable {
    let level: MemoryPressureLevel
    let freedMemory: Int64
    let duration: TimeInterval
    let modelsEvicted: [String]
    let success: Bool

    var freedMemoryString: String {
        ByteCountFormatter.string(fromByteCount: freedMemory, countStyle: .memory)
    }
}
