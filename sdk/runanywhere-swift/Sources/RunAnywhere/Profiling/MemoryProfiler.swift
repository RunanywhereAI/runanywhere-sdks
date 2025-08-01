//
//  MemoryProfiler.swift
//  RunAnywhere SDK
//
//  Advanced memory profiling infrastructure for on-device AI
//

import Foundation
import os.log

/// Advanced memory profiling tools for LLM frameworks
public class MemoryProfiler {
    public static let shared = MemoryProfiler()

    // MARK: - Properties

    /// Current memory profile
    public private(set) var currentProfile = MemoryProfile()

    /// Whether profiling is active
    public private(set) var isProfileActive = false

    /// Memory snapshots collected during profiling
    public private(set) var memorySnapshots: [MemorySnapshot] = []

    /// Detected memory leaks
    public private(set) var memoryLeaks: [MemoryLeak] = []

    // MARK: - Private Properties

    private let logger: os.Logger? = {
        if #available(iOS 14.0, *) {
            return os.Logger(subsystem: "com.runanywhere.sdk", category: "MemoryProfiler")
        } else {
            return nil
        }
    }()
    private var profilingTimer: Timer?
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.memoryprofiler", qos: .userInitiated)

    // Memory tracking
    private var allocationTracking: [String: AllocationInfo] = [:]
    private var baselineMemory: Int64 = 0
    private let snapshotInterval: TimeInterval = 0.5

    // Memory thresholds
    private let warningThreshold: Double = 0.75 // 75% of available memory
    private let criticalThreshold: Double = 0.90 // 90% of available memory

    // Profiling callbacks
    private var profilingCallbacks: [(MemorySnapshot) -> Void] = []

    // MARK: - Initialization

    private init() {
        setupMemoryMonitoring()
    }

    // MARK: - Public Methods

    /// Start memory profiling
    public func startProfiling() {
        queue.async { [weak self] in
            guard let self = self, !self.isProfileActive else { return }

            self.isProfileActive = true
            self.baselineMemory = self.getCurrentMemoryUsage()
            self.memorySnapshots.removeAll()
            self.memoryLeaks.removeAll()

            if #available(iOS 14.0, *) {
                self.logger?.info("Started memory profiling. Baseline: \(ByteCountFormatter.string(fromByteCount: self.baselineMemory, countStyle: .memory))")
            }

            // Start periodic snapshots on main queue for timer
            DispatchQueue.main.async {
                self.profilingTimer = Timer.scheduledTimer(withTimeInterval: self.snapshotInterval, repeats: true) { _ in
                    self.queue.async {
                        self.captureSnapshot()
                    }
                }
            }
        }
    }

    /// Stop memory profiling and generate report
    public func stopProfiling() -> MemoryProfilingReport {
        var report: MemoryProfilingReport!

        queue.sync { [weak self] in
            guard let self = self else { return }

            self.isProfileActive = false
            DispatchQueue.main.async {
                self.profilingTimer?.invalidate()
                self.profilingTimer = nil
            }

            if #available(iOS 14.0, *) {
                self.logger?.info("Stopped memory profiling")
            }
            report = self.generateReport()
        }

        return report
    }

    /// Profile memory for a specific operation
    public func profileOperation<T>(
        name: String,
        operation: () async throws -> T
    ) async throws -> (result: T, profile: OperationMemoryProfile) {
        let startMemory = getCurrentMemoryUsage()
        let startTime = CFAbsoluteTimeGetCurrent()

        // Track allocation
        let allocationId = UUID().uuidString
        queue.sync {
            beginAllocationTracking(id: allocationId, name: name)
        }

        do {
            let result = try await operation()

            let endMemory = getCurrentMemoryUsage()
            let endTime = CFAbsoluteTimeGetCurrent()

            // End tracking
            queue.sync {
                endAllocationTracking(id: allocationId)
            }

            let profile = OperationMemoryProfile(
                operationName: name,
                memoryUsed: endMemory - startMemory,
                peakMemory: getPeakMemory(since: startTime),
                duration: endTime - startTime,
                allocations: getAllocations(for: allocationId)
            )

            if #available(iOS 14.0, *) {
                logger?.info("""
                Memory profile for '\(name)':
                - Memory used: \(ByteCountFormatter.string(fromByteCount: profile.memoryUsed, countStyle: .memory))
                - Peak memory: \(ByteCountFormatter.string(fromByteCount: profile.peakMemory, countStyle: .memory))
                - Duration: \(String(format: "%.2f", profile.duration))s
                """)
            }

            return (result, profile)
        } catch {
            queue.sync {
                endAllocationTracking(id: allocationId)
            }
            throw error
        }
    }

    /// Track model loading memory
    public func trackModelLoading(
        framework: LLMFramework,
        modelInfo: ModelInfo
    ) -> ModelMemoryTracking {
        let tracking = ModelMemoryTracking(
            framework: framework,
            modelName: modelInfo.name,
            expectedSize: modelInfo.estimatedMemory,
            startMemory: getCurrentMemoryUsage(),
            startTime: Date()
        )

        return tracking
    }

    /// Complete model loading tracking
    public func completeModelTracking(_ tracking: ModelMemoryTracking) -> ModelMemoryProfile {
        let endMemory = getCurrentMemoryUsage()
        let actualMemoryUsed = endMemory - tracking.startMemory
        let loadTime = Date().timeIntervalSince(tracking.startTime)

        let profile = ModelMemoryProfile(
            framework: tracking.framework,
            modelName: tracking.modelName,
            expectedSize: tracking.expectedSize,
            actualMemoryUsed: actualMemoryUsed,
            memoryOverhead: actualMemoryUsed - tracking.expectedSize,
            loadTime: loadTime,
            compressionRatio: tracking.expectedSize > 0 ? Double(tracking.expectedSize) / Double(actualMemoryUsed) : 1.0
        )

        if #available(iOS 14.0, *) {
            logger?.info("""
                Model memory profile for \(tracking.framework.displayName):
                - Model: \(tracking.modelName)
                - Expected size: \(ByteCountFormatter.string(fromByteCount: tracking.expectedSize, countStyle: .memory))
                - Actual memory: \(ByteCountFormatter.string(fromByteCount: actualMemoryUsed, countStyle: .memory))
                - Overhead: \(ByteCountFormatter.string(fromByteCount: profile.memoryOverhead, countStyle: .memory))
                - Compression ratio: \(String(format: "%.2f", profile.compressionRatio))
                """)
        }

        return profile
    }

    /// Detect memory leaks
    public func detectLeaks() -> [MemoryLeak] {
        queue.sync {
            var detectedLeaks: [MemoryLeak] = []

            // Check for growing allocations
            for (id, allocation) in allocationTracking {
                if allocation.isActive && allocation.duration > 60 { // Active for > 60 seconds
                    let growthRate = allocation.currentSize > allocation.initialSize ?
                        Double(allocation.currentSize - allocation.initialSize) / allocation.duration : 0

                    if growthRate > 1_000_000 { // Growing > 1MB/sec
                        detectedLeaks.append(
                            MemoryLeak(
                                id: id,
                                name: allocation.name,
                                initialSize: allocation.initialSize,
                                currentSize: allocation.currentSize,
                                growthRate: growthRate,
                                duration: allocation.duration
                            )
                        )
                    }
                }
            }

            memoryLeaks = detectedLeaks

            if !detectedLeaks.isEmpty {
                if #available(iOS 14.0, *) {
                    logger?.warning("Detected \(detectedLeaks.count) potential memory leaks")
                }
            }

            return detectedLeaks
        }
    }

    /// Get memory recommendations based on current usage
    public func getRecommendations() -> [MemoryRecommendation] {
        var recommendations: [MemoryRecommendation] = []

        let currentUsage = getCurrentMemoryUsage()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usageRatio = Double(currentUsage) / Double(totalMemory)

        // High memory usage
        if usageRatio > warningThreshold {
            recommendations.append(
                MemoryRecommendation(
                    type: .highMemoryUsage,
                    severity: usageRatio > criticalThreshold ? .critical : .warning,
                    message: "Memory usage is at \(Int(usageRatio * 100))%. Consider unloading unused models.",
                    action: .unloadModels
                )
            )
        }

        // Memory leaks
        if !memoryLeaks.isEmpty {
            recommendations.append(
                MemoryRecommendation(
                    type: .memoryLeak,
                    severity: .critical,
                    message: "Detected \(memoryLeaks.count) potential memory leaks",
                    action: .restartApp
                )
            )
        }

        // Fragmentation
        if let fragmentation = calculateFragmentation(), fragmentation > 0.3 {
            recommendations.append(
                MemoryRecommendation(
                    type: .fragmentation,
                    severity: .warning,
                    message: "Memory fragmentation at \(Int(fragmentation * 100))%",
                    action: .compactMemory
                )
            )
        }

        return recommendations
    }

    /// Add callback for memory snapshots
    public func addSnapshotCallback(_ callback: @escaping (MemorySnapshot) -> Void) {
        queue.async { [weak self] in
            self?.profilingCallbacks.append(callback)
        }
    }

    /// Get current memory statistics
    public func getCurrentStats() -> MemoryStats {
        let current = getCurrentMemoryUsage()
        let available = getAvailableMemory()
        let total = ProcessInfo.processInfo.physicalMemory

        return MemoryStats(
            usedMemory: current,
            availableMemory: available,
            totalMemory: Int64(total),
            usagePercentage: Double(current) / Double(total),
            pressure: getMemoryPressure()
        )
    }

    // MARK: - Private Methods

    private func setupMemoryMonitoring() {
        // Monitor memory warnings
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }

    private func captureSnapshot() {
        let snapshot = MemorySnapshot(
            timestamp: Date(),
            usedMemory: getCurrentMemoryUsage(),
            availableMemory: getAvailableMemory(),
            allocations: allocationTracking.count,
            pressure: getMemoryPressure()
        )

        memorySnapshots.append(snapshot)

        // Keep only last 5 minutes of snapshots
        let cutoff = Date().addingTimeInterval(-300)
        memorySnapshots = memorySnapshots.filter { $0.timestamp > cutoff }

        // Update current profile
        currentProfile = MemoryProfile(
            currentUsage: snapshot.usedMemory,
            peakUsage: memorySnapshots.map { $0.usedMemory }.max() ?? 0,
            baseline: baselineMemory,
            snapshots: memorySnapshots
        )

        // Notify callbacks
        for callback in profilingCallbacks {
            callback(snapshot)
        }
    }

    private func beginAllocationTracking(id: String, name: String) {
        allocationTracking[id] = AllocationInfo(
            id: id,
            name: name,
            initialSize: getCurrentMemoryUsage(),
            currentSize: getCurrentMemoryUsage(),
            startTime: Date(),
            isActive: true
        )
    }

    private func endAllocationTracking(id: String) {
        if var allocation = allocationTracking[id] {
            allocation.isActive = false
            allocation.currentSize = getCurrentMemoryUsage()
            allocationTracking[id] = allocation
        }
    }

    private func getAllocations(for id: String) -> [AllocationInfo] {
        if let allocation = allocationTracking[id] {
            return [allocation]
        }
        return []
    }

    private func getPeakMemory(since startTime: CFAbsoluteTime) -> Int64 {
        let relevantSnapshots = memorySnapshots.filter {
            $0.timestamp.timeIntervalSince1970 >= startTime
        }
        return relevantSnapshots.map { $0.usedMemory }.max() ?? getCurrentMemoryUsage()
    }

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func getAvailableMemory() -> Int64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        return Int64(totalMemory) - usedMemory
    }

    private func getMemoryPressure() -> MemoryPressure {
        let usageRatio = Double(getCurrentMemoryUsage()) / Double(ProcessInfo.processInfo.physicalMemory)

        switch usageRatio {
        case 0..<0.5:
            return .normal
        case 0.5..<0.75:
            return .warning
        case 0.75..<0.9:
            return .urgent
        default:
            return .critical
        }
    }

    private func calculateFragmentation() -> Double? {
        // Simplified fragmentation calculation
        // In production, would analyze heap structure
        return nil
    }

    private func generateReport() -> MemoryProfilingReport {
        let endMemory = getCurrentMemoryUsage()
        let totalAllocated = endMemory - baselineMemory

        return MemoryProfilingReport(
            startTime: memorySnapshots.first?.timestamp ?? Date(),
            endTime: Date(),
            baselineMemory: baselineMemory,
            peakMemory: memorySnapshots.map { $0.usedMemory }.max() ?? endMemory,
            endMemory: endMemory,
            totalAllocated: totalAllocated,
            leaksDetected: memoryLeaks.count,
            snapshots: memorySnapshots,
            recommendations: getRecommendations()
        )
    }

    @objc private func handleMemoryWarning() {
        if #available(iOS 14.0, *) {
            logger?.warning("Received system memory warning")
        }

        // Capture critical snapshot
        captureSnapshot()

        // Force leak detection
        _ = detectLeaks()
    }
}

// MARK: - Supporting Types

/// Current memory profile
public struct MemoryProfile {
    public let currentUsage: Int64
    public let peakUsage: Int64
    public let baseline: Int64
    public let snapshots: [MemorySnapshot]

    public init(
        currentUsage: Int64 = 0,
        peakUsage: Int64 = 0,
        baseline: Int64 = 0,
        snapshots: [MemorySnapshot] = []
    ) {
        self.currentUsage = currentUsage
        self.peakUsage = peakUsage
        self.baseline = baseline
        self.snapshots = snapshots
    }
}

/// Memory snapshot at a point in time
public struct MemorySnapshot {
    public let timestamp: Date
    public let usedMemory: Int64
    public let availableMemory: Int64
    public let allocations: Int
    public let pressure: MemoryPressure
}

/// Memory allocation information
public struct AllocationInfo {
    public let id: String
    public let name: String
    public let initialSize: Int64
    public var currentSize: Int64
    public let startTime: Date
    public var isActive: Bool

    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

/// Detected memory leak
public struct MemoryLeak {
    public let id: String
    public let name: String
    public let initialSize: Int64
    public let currentSize: Int64
    public let growthRate: Double // bytes per second
    public let duration: TimeInterval
}

/// Model memory tracking
public struct ModelMemoryTracking {
    public let framework: LLMFramework
    public let modelName: String
    public let expectedSize: Int64
    public let startMemory: Int64
    public let startTime: Date
}

/// Model memory profile
public struct ModelMemoryProfile {
    public let framework: LLMFramework
    public let modelName: String
    public let expectedSize: Int64
    public let actualMemoryUsed: Int64
    public let memoryOverhead: Int64
    public let loadTime: TimeInterval
    public let compressionRatio: Double
}

/// Operation memory profile
public struct OperationMemoryProfile {
    public let operationName: String
    public let memoryUsed: Int64
    public let peakMemory: Int64
    public let duration: TimeInterval
    public let allocations: [AllocationInfo]
}

/// Memory recommendation
public struct MemoryRecommendation {
    public let type: RecommendationType
    public let severity: RecommendationSeverity
    public let message: String
    public let action: RecommendedAction

    public enum RecommendationType {
        case highMemoryUsage
        case memoryLeak
        case fragmentation
        case inefficientAllocation
    }

    public enum RecommendationSeverity {
        case info
        case warning
        case critical
    }

    public enum RecommendedAction {
        case unloadModels
        case restartApp
        case compactMemory
        case optimizeAllocations
    }
}

/// Memory statistics
public struct MemoryStats {
    public let usedMemory: Int64
    public let availableMemory: Int64
    public let totalMemory: Int64
    public let usagePercentage: Double
    public let pressure: MemoryPressure
}

/// Memory pressure levels
public enum MemoryPressure {
    case normal
    case warning
    case urgent
    case critical
}

/// Complete memory profiling report
public struct MemoryProfilingReport {
    public let startTime: Date
    public let endTime: Date
    public let baselineMemory: Int64
    public let peakMemory: Int64
    public let endMemory: Int64
    public let totalAllocated: Int64
    public let leaksDetected: Int
    public let snapshots: [MemorySnapshot]
    public let recommendations: [MemoryRecommendation]
}

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif
