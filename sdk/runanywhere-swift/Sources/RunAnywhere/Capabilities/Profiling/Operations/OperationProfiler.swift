//
//  OperationProfiler.swift
//  RunAnywhere SDK
//
//  Profiles memory usage for specific operations
//

import Foundation

/// Profiles memory usage for specific operations
class OperationProfiler {
    private let allocationTracker: AllocationTracker
    private let logger = SDKLogger(category: "OperationProfiler")

    init(allocationTracker: AllocationTracker) {
        self.allocationTracker = allocationTracker
    }

    /// Profile a synchronous operation
    func profileSync<T>(
        name: String,
        operation: () throws -> T
    ) throws -> (result: T, profile: OperationMemoryProfile) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
        let operationId = UUID().uuidString

        allocationTracker.beginTracking(id: operationId, name: name)

        defer {
            allocationTracker.endTracking(id: operationId)
        }

        let result = try operation()

        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()

        let allocations = allocationTracker.getAllocations(for: operationId)

        let profile = OperationMemoryProfile(
            operationName: name,
            memoryUsed: endMemory - startMemory,
            peakMemory: endMemory, // Simplified for sync operations
            duration: endTime - startTime,
            allocations: allocations
        )

        logger.info("Operation '\(name)' used \(ByteCountFormatter.string(fromByteCount: profile.memoryUsed, countStyle: .memory)) in \(String(format: "%.2f", profile.duration))s")

        return (result, profile)
    }

    /// Profile an asynchronous operation
    func profileAsync<T>(
        name: String,
        operation: () async throws -> T
    ) async throws -> (result: T, profile: OperationMemoryProfile) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()
        let operationId = UUID().uuidString

        allocationTracker.beginTracking(id: operationId, name: name)

        defer {
            allocationTracker.endTracking(id: operationId)
        }

        // Track peak memory during async operation
        var peakMemory = startMemory
        let monitorTask = Task {
            while !Task.isCancelled {
                let current = ProfilerSystemMetrics.getCurrentMemoryUsage()
                if current > peakMemory {
                    peakMemory = current
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        let result = try await operation()
        monitorTask.cancel()

        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = ProfilerSystemMetrics.getCurrentMemoryUsage()

        let allocations = allocationTracker.getAllocations(for: operationId)

        let profile = OperationMemoryProfile(
            operationName: name,
            memoryUsed: endMemory - startMemory,
            peakMemory: peakMemory,
            duration: endTime - startTime,
            allocations: allocations
        )

        logger.info("Async operation '\(name)' used \(ByteCountFormatter.string(fromByteCount: profile.memoryUsed, countStyle: .memory)) in \(String(format: "%.2f", profile.duration))s")

        return (result, profile)
    }

    /// Create a lightweight operation profile without full tracking
    func createLightweightProfile(
        name: String,
        startMemory: Int64,
        endMemory: Int64,
        duration: TimeInterval
    ) -> OperationMemoryProfile {
        OperationMemoryProfile(
            operationName: name,
            memoryUsed: endMemory - startMemory,
            peakMemory: max(startMemory, endMemory),
            duration: duration,
            allocations: []
        )
    }
}
