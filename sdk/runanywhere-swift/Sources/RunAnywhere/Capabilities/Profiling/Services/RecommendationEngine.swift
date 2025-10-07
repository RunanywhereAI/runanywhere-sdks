//
//  RecommendationEngine.swift
//  RunAnywhere SDK
//
//  Generates memory optimization recommendations
//

import Foundation

/// Generates memory optimization recommendations based on profiling data
class RecommendationEngine {
    private let logger = SDKLogger(category: "RecommendationEngine")

    // Thresholds for recommendations
    private let warningThreshold: Double = 0.75 // 75% memory usage
    private let criticalThreshold: Double = 0.90 // 90% memory usage
    private let fragmentationThreshold: Double = 0.30 // 30% fragmentation

    /// Generate recommendations based on current memory state
    func generateRecommendations(
        stats: MemoryStats,
        leaks: [MemoryLeak],
        snapshots: [MemorySnapshot]
    ) -> [MemoryRecommendation] {
        var recommendations: [MemoryRecommendation] = []

        // Check memory usage
        recommendations.append(contentsOf: checkMemoryUsage(stats))

        // Check for leaks
        recommendations.append(contentsOf: checkMemoryLeaks(leaks))

        // Check fragmentation
        recommendations.append(contentsOf: checkFragmentation(stats))

        // Check memory pressure trends
        recommendations.append(contentsOf: checkMemoryTrends(snapshots))

        // Sort by severity
        return recommendations.sorted {
            $0.severity.rawValue > $1.severity.rawValue
        }
    }

    private func checkMemoryUsage(_ stats: MemoryStats) -> [MemoryRecommendation] {
        var recommendations: [MemoryRecommendation] = []

        if stats.usagePercentage > criticalThreshold {
            recommendations.append(
                MemoryRecommendation(
                    type: .highMemoryUsage,
                    severity: .critical,
                    message: "Critical memory usage at \(Int(stats.usagePercentage * 100))%. Immediate action required.",
                    action: .unloadModels
                )
            )
        } else if stats.usagePercentage > warningThreshold {
            recommendations.append(
                MemoryRecommendation(
                    type: .highMemoryUsage,
                    severity: .warning,
                    message: "High memory usage at \(Int(stats.usagePercentage * 100))%. Consider unloading unused models.",
                    action: .unloadModels
                )
            )
        }

        return recommendations
    }

    private func checkMemoryLeaks(_ leaks: [MemoryLeak]) -> [MemoryRecommendation] {
        guard !leaks.isEmpty else { return [] }

        let totalLeakedMemory = leaks.reduce(0) { $0 + $1.currentSize }
        let criticalLeaks = leaks.filter { $0.growthRate > 2_000_000 } // 2MB/sec

        if !criticalLeaks.isEmpty {
            return [
                MemoryRecommendation(
                    type: .memoryLeak,
                    severity: .critical,
                    message: "Detected \(criticalLeaks.count) critical memory leaks losing \(ByteCountFormatter.string(fromByteCount: totalLeakedMemory, countStyle: .memory))",
                    action: .restartApp
                )
            ]
        } else {
            return [
                MemoryRecommendation(
                    type: .memoryLeak,
                    severity: .warning,
                    message: "Detected \(leaks.count) potential memory leaks",
                    action: .restartApp
                )
            ]
        }
    }

    private func checkFragmentation(_ stats: MemoryStats) -> [MemoryRecommendation] {
        // Simplified fragmentation check based on memory pressure
        if stats.pressure == .critical {
            return [
                MemoryRecommendation(
                    type: .fragmentation,
                    severity: .warning,
                    message: "High memory pressure detected. Memory may be fragmented.",
                    action: .compactMemory
                )
            ]
        }
        return []
    }

    private func checkMemoryTrends(_ snapshots: [MemorySnapshot]) -> [MemoryRecommendation] {
        guard snapshots.count >= 10 else { return [] }

        // Check if memory is consistently increasing
        let recentSnapshots = snapshots.suffix(10)
        let firstMemory = recentSnapshots.first?.usedMemory ?? 0
        let lastMemory = recentSnapshots.last?.usedMemory ?? 0

        let growthRate = Double(lastMemory - firstMemory) / Double(recentSnapshots.count)

        if growthRate > 5_000_000 { // Growing > 5MB per snapshot
            return [
                MemoryRecommendation(
                    type: .inefficientAllocation,
                    severity: .warning,
                    message: "Memory usage growing rapidly at \(ByteCountFormatter.string(fromByteCount: Int64(growthRate), countStyle: .memory))/snapshot",
                    action: .optimizeAllocations
                )
            ]
        }

        return []
    }
}

extension RecommendationSeverity: Comparable {
    var rawValue: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: RecommendationSeverity, rhs: RecommendationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
