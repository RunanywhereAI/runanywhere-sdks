//
//  HistoryManager.swift
//  RunAnywhere SDK
//
//  Manages performance history
//

import Foundation

/// Manages performance history snapshots
internal class HistoryManager {
    private let historyLimit: Int
    private var snapshots: [PerformanceSnapshot] = []
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.historymanager")

    init(historyLimit: Int = 300) {
        self.historyLimit = historyLimit
    }

    /// Add a new snapshot
    func addSnapshot(_ snapshot: PerformanceSnapshot) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.snapshots.append(snapshot)

            // Maintain history limit
            if self.snapshots.count > self.historyLimit {
                self.snapshots.removeFirst()
            }
        }
    }

    /// Get all snapshots
    func getAllSnapshots() -> [PerformanceSnapshot] {
        queue.sync {
            return snapshots
        }
    }

    /// Get snapshots within a time range
    func getSnapshots(withinTimeRange timeRange: TimeInterval) -> [PerformanceSnapshot] {
        queue.sync {
            let cutoffTime = Date().timeIntervalSince1970 - timeRange
            return snapshots.filter { $0.timestamp.timeIntervalSince1970 > cutoffTime }
        }
    }

    /// Calculate statistics for snapshots
    func calculateStatistics(for snapshots: [PerformanceSnapshot]) -> (
        avgMemory: Int64,
        peakMemory: Int64,
        avgCPU: Double,
        peakCPU: Double
    ) {
        guard !snapshots.isEmpty else {
            return (0, 0, 0, 0)
        }

        let memoryUsages = snapshots.map { $0.memoryUsage }
        let cpuUsages = snapshots.map { $0.cpuUsage }

        let avgMemory = memoryUsages.reduce(0, +) / Int64(memoryUsages.count)
        let peakMemory = memoryUsages.max() ?? 0
        let avgCPU = cpuUsages.reduce(0, +) / Double(cpuUsages.count)
        let peakCPU = cpuUsages.max() ?? 0

        return (avgMemory, peakMemory, avgCPU, peakCPU)
    }

    /// Clear all history
    func clearHistory() {
        queue.async { [weak self] in
            self?.snapshots.removeAll()
        }
    }
}
