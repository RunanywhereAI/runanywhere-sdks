//
//  SnapshotManager.swift
//  RunAnywhere SDK
//
//  Manages memory snapshots during profiling
//

import Foundation

/// Manages memory snapshots during profiling sessions
class SnapshotManager {
    private let logger = SDKLogger(category: "SnapshotManager")
    private var snapshots: [MemorySnapshot] = []
    private let maxSnapshots = 600 // 5 minutes at 0.5s intervals
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.snapshots", attributes: .concurrent)

    /// Current snapshots
    var currentSnapshots: [MemorySnapshot] {
        queue.sync { snapshots }
    }

    /// Add a new snapshot
    func addSnapshot(_ snapshot: MemorySnapshot) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.snapshots.append(snapshot)

            // Keep only recent snapshots
            if self.snapshots.count > self.maxSnapshots {
                self.snapshots.removeFirst(self.snapshots.count - self.maxSnapshots)
            }
        }
    }

    /// Capture current memory snapshot
    func captureSnapshot() -> MemorySnapshot {
        let snapshot = MemorySnapshot(
            timestamp: Date(),
            usedMemory: SystemMetrics.getCurrentMemoryUsage(),
            availableMemory: SystemMetrics.getAvailableMemory(),
            allocations: 0, // Will be updated by caller if needed
            pressure: SystemMetrics.getMemoryPressure()
        )

        addSnapshot(snapshot)
        return snapshot
    }

    /// Get snapshots within time range
    func getSnapshots(from startTime: Date, to endTime: Date) -> [MemorySnapshot] {
        queue.sync {
            snapshots.filter { snapshot in
                snapshot.timestamp >= startTime && snapshot.timestamp <= endTime
            }
        }
    }

    /// Get recent snapshots
    func getRecentSnapshots(duration: TimeInterval) -> [MemorySnapshot] {
        let cutoff = Date().addingTimeInterval(-duration)
        return queue.sync {
            snapshots.filter { $0.timestamp > cutoff }
        }
    }

    /// Clear all snapshots
    func clearSnapshots() {
        queue.async(flags: .barrier) { [weak self] in
            self?.snapshots.removeAll()
        }
    }

    /// Get memory statistics from snapshots
    func getStatistics() -> SnapshotStatistics? {
        let currentSnapshots = self.currentSnapshots
        guard !currentSnapshots.isEmpty else { return nil }

        let memoryValues = currentSnapshots.map { $0.usedMemory }
        let minMemory = memoryValues.min() ?? 0
        let maxMemory = memoryValues.max() ?? 0
        let avgMemory = memoryValues.reduce(0, +) / Int64(memoryValues.count)

        let firstSnapshot = currentSnapshots.first!
        let lastSnapshot = currentSnapshots.last!
        let duration = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)

        return SnapshotStatistics(
            snapshotCount: currentSnapshots.count,
            duration: duration,
            minMemory: minMemory,
            maxMemory: maxMemory,
            averageMemory: avgMemory,
            memoryGrowth: lastSnapshot.usedMemory - firstSnapshot.usedMemory
        )
    }
}

/// Statistics derived from memory snapshots
struct SnapshotStatistics {
    let snapshotCount: Int
    let duration: TimeInterval
    let minMemory: Int64
    let maxMemory: Int64
    let averageMemory: Int64
    let memoryGrowth: Int64

    var growthRate: Double {
        duration > 0 ? Double(memoryGrowth) / duration : 0
    }
}
