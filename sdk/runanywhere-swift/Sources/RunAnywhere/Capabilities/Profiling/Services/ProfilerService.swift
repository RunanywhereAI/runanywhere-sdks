//
//  ProfilerService.swift
//  RunAnywhere SDK
//
//  Main memory profiling service implementation
//

import Foundation

/// Main memory profiling service
public class ProfilerService: MemoryProfiler {
    public static let shared = ProfilerService()

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

    private let logger = SDKLogger(category: "ProfilerService")
    private var profilingTimer: Timer?
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.profiler", qos: .userInitiated)

    // Allocation tracking
    private let allocationTracker: AllocationTracker

    // Leak detection
    private let leakDetector: LeakDetector

    // Recommendation engine
    private let recommendationEngine: RecommendationEngine

    // Memory tracking
    private var baselineMemory: Int64 = 0
    private let snapshotInterval: TimeInterval = 0.5

    // Profiling callbacks
    private var profilingCallbacks: [(MemorySnapshot) -> Void] = []

    // MARK: - Initialization

    private init() {
        self.allocationTracker = AllocationTracker()
        self.leakDetector = LeakDetector()
        self.recommendationEngine = RecommendationEngine()
        setupMemoryMonitoring()
    }

    // MARK: - MemoryProfiler Protocol

    public func startProfiling() {
        queue.async { [weak self] in
            guard let self = self, !self.isProfileActive else { return }

            self.isProfileActive = true
            self.baselineMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
            self.memorySnapshots.removeAll()
            self.memoryLeaks.removeAll()

            self.logger.info("Started memory profiling. Baseline: \(ByteCountFormatter.string(fromByteCount: self.baselineMemory, countStyle: .memory))")

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

    public func stopProfiling() -> MemoryProfilingReport {
        var report: MemoryProfilingReport!

        queue.sync { [weak self] in
            guard let self = self else { return }

            self.isProfileActive = false
            DispatchQueue.main.async {
                self.profilingTimer?.invalidate()
                self.profilingTimer = nil
            }

            self.logger.info("Stopped memory profiling")
            report = self.generateReport()
        }

        return report
    }

    public func profileOperation<T>(
        name: String,
        operation: () async throws -> T
    ) async throws -> (result: T, profile: OperationMemoryProfile) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
        let operationId = UUID().uuidString

        allocationTracker.beginTracking(id: operationId, name: name)

        let result = try await operation()

        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
        allocationTracker.endTracking(id: operationId)

        let allocations = allocationTracker.getAllocations(for: operationId)
        let peakMemory = getPeakMemory(since: startTime)

        let profile = OperationMemoryProfile(
            operationName: name,
            memoryUsed: endMemory - startMemory,
            peakMemory: peakMemory,
            duration: endTime - startTime,
            allocations: allocations
        )

        return (result, profile)
    }

    public func profileModelLoading(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64,
        loadOperation: () async throws -> Void
    ) async throws -> ModelMemoryProfile {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()

        try await loadOperation()

        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()

        let actualMemoryUsed = endMemory - startMemory
        let memoryOverhead = actualMemoryUsed - expectedSize
        let compressionRatio = Double(expectedSize) / Double(actualMemoryUsed)

        return ModelMemoryProfile(
            framework: framework,
            modelName: modelName,
            expectedSize: expectedSize,
            actualMemoryUsed: actualMemoryUsed,
            memoryOverhead: memoryOverhead,
            loadTime: endTime - startTime,
            compressionRatio: compressionRatio
        )
    }

    public func detectLeaks() -> [MemoryLeak] {
        queue.sync {
            let detectedLeaks = leakDetector.detectLeaks(from: allocationTracker.activeAllocations)
            memoryLeaks = detectedLeaks

            if !detectedLeaks.isEmpty {
                logger.warning("Detected \(detectedLeaks.count) potential memory leaks")
            }

            return detectedLeaks
        }
    }

    public func getRecommendations() -> [MemoryRecommendation] {
        let currentStats = getCurrentStats()
        return recommendationEngine.generateRecommendations(
            stats: currentStats,
            leaks: memoryLeaks,
            snapshots: memorySnapshots
        )
    }

    public func addSnapshotCallback(_ callback: @escaping (MemorySnapshot) -> Void) {
        queue.async { [weak self] in
            self?.profilingCallbacks.append(callback)
        }
    }

    public func getCurrentStats() -> MemoryStats {
        let current = ProfilerSystemMetrics.getCurrentMemoryUsage()
        let available = ProfilerSystemMetrics.getAvailableMemory()
        let total = ProcessInfo.processInfo.physicalMemory

        return MemoryStats(
            usedMemory: current,
            availableMemory: available,
            totalMemory: Int64(total),
            usagePercentage: Double(current) / Double(total),
            pressure: ProfilerSystemMetrics.getMemoryPressure()
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
            usedMemory: ProfilerSystemMetrics.getCurrentMemoryUsage(),
            availableMemory: ProfilerSystemMetrics.getAvailableMemory(),
            allocations: allocationTracker.activeAllocations.count,
            pressure: ProfilerSystemMetrics.getMemoryPressure()
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

    private func getPeakMemory(since startTime: CFAbsoluteTime) -> Int64 {
        let relevantSnapshots = memorySnapshots.filter {
            $0.timestamp.timeIntervalSince1970 >= startTime
        }
        return relevantSnapshots.map { $0.usedMemory }.max() ?? ProfilerSystemMetrics.getCurrentMemoryUsage()
    }

    private func generateReport() -> MemoryProfilingReport {
        let endMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
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
        logger.warning("Received system memory warning")

        // Capture critical snapshot
        captureSnapshot()

        // Force leak detection
        _ = detectLeaks()
    }
}

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif
