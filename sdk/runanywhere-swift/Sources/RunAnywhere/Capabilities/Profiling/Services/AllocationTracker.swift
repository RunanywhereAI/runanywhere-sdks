//
//  AllocationTracker.swift
//  RunAnywhere SDK
//
//  Tracks memory allocations during profiling
//

import Foundation

/// Tracks memory allocations during profiling sessions
class AllocationTracker {
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.allocation", attributes: .concurrent)
    private var allocations: [String: AllocationInfo] = [:]

    /// Active allocations
    var activeAllocations: [String: AllocationInfo] {
        queue.sync {
            allocations.filter { $0.value.isActive }
        }
    }

    /// Begin tracking an allocation
    func beginTracking(id: String, name: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.allocations[id] = AllocationInfo(
                id: id,
                name: name,
                initialSize: ProfilerSystemMetrics.getCurrentMemoryUsage(),
                currentSize: ProfilerSystemMetrics.getCurrentMemoryUsage(),
                startTime: Date(),
                isActive: true
            )
        }
    }

    /// End tracking for an allocation
    func endTracking(id: String) {
        queue.async(flags: .barrier) { [weak self] in
            if var allocation = self?.allocations[id] {
                allocation.isActive = false
                allocation.currentSize = ProfilerSystemMetrics.getCurrentMemoryUsage()
                self?.allocations[id] = allocation
            }
        }
    }

    /// Update allocation size
    func updateAllocation(id: String, size: Int64) {
        queue.async(flags: .barrier) { [weak self] in
            if var allocation = self?.allocations[id] {
                allocation.currentSize = size
                self?.allocations[id] = allocation
            }
        }
    }

    /// Get allocations for a specific ID
    func getAllocations(for id: String) -> [AllocationInfo] {
        queue.sync {
            if let allocation = allocations[id] {
                return [allocation]
            }
            return []
        }
    }

    /// Get all allocations
    func getAllAllocations() -> [AllocationInfo] {
        queue.sync {
            Array(allocations.values)
        }
    }

    /// Clear all allocations
    func clearAllocations() {
        queue.async(flags: .barrier) { [weak self] in
            self?.allocations.removeAll()
        }
    }

    /// Get allocations exceeding a size threshold
    func getLargeAllocations(threshold: Int64) -> [AllocationInfo] {
        queue.sync {
            allocations.values.filter { $0.currentSize > threshold }
        }
    }
}
