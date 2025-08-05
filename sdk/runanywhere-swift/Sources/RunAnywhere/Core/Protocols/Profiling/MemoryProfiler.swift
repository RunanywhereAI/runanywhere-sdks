//
//  MemoryProfiler.swift
//  RunAnywhere SDK
//
//  Protocol for memory profiling functionality
//

import Foundation

/// Protocol defining memory profiling capabilities
public protocol MemoryProfiler {
    /// Whether profiling is currently active
    var isProfileActive: Bool { get }

    /// Start memory profiling
    func startProfiling()

    /// Stop memory profiling and generate report
    func stopProfiling() -> MemoryProfilingReport

    /// Profile memory for a specific operation
    func profileOperation<T>(
        name: String,
        operation: () async throws -> T
    ) async throws -> (result: T, profile: OperationMemoryProfile)

    /// Profile model loading
    func profileModelLoading(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64,
        loadOperation: () async throws -> Void
    ) async throws -> ModelMemoryProfile

    /// Detect memory leaks
    func detectLeaks() -> [MemoryLeak]

    /// Get memory recommendations
    func getRecommendations() -> [MemoryRecommendation]

    /// Add callback for memory snapshots
    func addSnapshotCallback(_ callback: @escaping (MemorySnapshot) -> Void)

    /// Get current memory statistics
    func getCurrentStats() -> MemoryStats
}

/// Memory statistics
public struct MemoryStats {
    public let usedMemory: Int64
    public let availableMemory: Int64
    public let totalMemory: Int64
    public let usagePercentage: Double
    public let pressure: MemoryPressure

    public init(
        usedMemory: Int64,
        availableMemory: Int64,
        totalMemory: Int64,
        usagePercentage: Double,
        pressure: MemoryPressure
    ) {
        self.usedMemory = usedMemory
        self.availableMemory = availableMemory
        self.totalMemory = totalMemory
        self.usagePercentage = usagePercentage
        self.pressure = pressure
    }
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

    public init(
        startTime: Date,
        endTime: Date,
        baselineMemory: Int64,
        peakMemory: Int64,
        endMemory: Int64,
        totalAllocated: Int64,
        leaksDetected: Int,
        snapshots: [MemorySnapshot],
        recommendations: [MemoryRecommendation]
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.baselineMemory = baselineMemory
        self.peakMemory = peakMemory
        self.endMemory = endMemory
        self.totalAllocated = totalAllocated
        self.leaksDetected = leaksDetected
        self.snapshots = snapshots
        self.recommendations = recommendations
    }
}
