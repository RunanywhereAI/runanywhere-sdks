//
//  MemoryAnalyzer.swift
//  RunAnywhere SDK
//
//  Analyzes memory usage patterns
//

import Foundation

/// Analyzes memory usage patterns and trends
class MemoryAnalyzer {
    private let logger = SDKLogger(category: "MemoryAnalyzer")

    /// Analyze memory usage patterns from snapshots
    func analyzePatterns(snapshots: [MemorySnapshot]) -> MemoryUsagePattern {
        guard !snapshots.isEmpty else {
            return MemoryUsagePattern(
                trend: .stable,
                volatility: 0,
                peakTimes: [],
                averageGrowthRate: 0
            )
        }

        let trend = analyzeTrend(snapshots)
        let volatility = calculateVolatility(snapshots)
        let peakTimes = findPeakTimes(snapshots)
        let growthRate = calculateGrowthRate(snapshots)

        return MemoryUsagePattern(
            trend: trend,
            volatility: volatility,
            peakTimes: peakTimes,
            averageGrowthRate: growthRate
        )
    }

    /// Analyze allocation patterns
    func analyzeAllocations(_ allocations: [AllocationInfo]) -> AllocationPattern {
        let totalAllocations = allocations.count
        let activeAllocations = allocations.filter { $0.isActive }.count
        let totalSize = allocations.reduce(0) { $0 + $0.currentSize }
        let largestAllocation = allocations.max(by: { $0.currentSize < $1.currentSize })

        let averageSize = totalAllocations > 0 ? totalSize / Int64(totalAllocations) : 0
        let fragmentationRatio = calculateFragmentationRatio(allocations)

        return AllocationPattern(
            totalAllocations: totalAllocations,
            activeAllocations: activeAllocations,
            totalSize: totalSize,
            averageSize: averageSize,
            largestAllocation: largestAllocation,
            fragmentationRatio: fragmentationRatio
        )
    }

    /// Identify memory usage anomalies
    func detectAnomalies(snapshots: [MemorySnapshot]) -> [MemoryAnomaly] {
        guard snapshots.count >= 10 else { return [] }

        var anomalies: [MemoryAnomaly] = []

        // Calculate baseline statistics
        let memoryValues = snapshots.map { $0.usedMemory }
        let mean = Double(memoryValues.reduce(0, +)) / Double(memoryValues.count)
        let variance = memoryValues.reduce(0.0) { acc, value in
            let diff = Double(value) - mean
            return acc + (diff * diff)
        } / Double(memoryValues.count)
        let stdDev = sqrt(variance)

        // Detect spikes (3 standard deviations from mean)
        for (index, snapshot) in snapshots.enumerated() {
            let deviation = abs(Double(snapshot.usedMemory) - mean)
            if deviation > stdDev * 3 {
                anomalies.append(
                    MemoryAnomaly(
                        timestamp: snapshot.timestamp,
                        type: .spike,
                        severity: deviation > stdDev * 4 ? .high : .medium,
                        memoryValue: snapshot.usedMemory,
                        expectedValue: Int64(mean)
                    )
                )
            }

            // Detect sudden drops
            if index > 0 {
                let previousMemory = snapshots[index - 1].usedMemory
                let drop = previousMemory - snapshot.usedMemory
                if drop > Int64(mean * 0.3) { // 30% drop
                    anomalies.append(
                        MemoryAnomaly(
                            timestamp: snapshot.timestamp,
                            type: .suddenDrop,
                            severity: .low,
                            memoryValue: snapshot.usedMemory,
                            expectedValue: previousMemory
                        )
                    )
                }
            }
        }

        return anomalies
    }

    // MARK: - Private Methods

    private func analyzeTrend(_ snapshots: [MemorySnapshot]) -> MemoryTrend {
        guard snapshots.count >= 2 else { return .stable }

        let firstMemory = Double(snapshots.first!.usedMemory)
        let lastMemory = Double(snapshots.last!.usedMemory)
        let percentChange = ((lastMemory - firstMemory) / firstMemory) * 100

        switch percentChange {
        case ..<(-10):
            return .decreasing
        case -10..<10:
            return .stable
        case 10..<50:
            return .increasing
        default:
            return .rapidlyIncreasing
        }
    }

    private func calculateVolatility(_ snapshots: [MemorySnapshot]) -> Double {
        guard snapshots.count >= 2 else { return 0 }

        var changes: [Double] = []
        for i in 1..<snapshots.count {
            let change = Double(snapshots[i].usedMemory - snapshots[i-1].usedMemory)
            changes.append(abs(change))
        }

        let averageChange = changes.reduce(0, +) / Double(changes.count)
        let averageMemory = Double(snapshots.map { $0.usedMemory }.reduce(0, +)) / Double(snapshots.count)

        return averageMemory > 0 ? averageChange / averageMemory : 0
    }

    private func findPeakTimes(_ snapshots: [MemorySnapshot]) -> [Date] {
        guard !snapshots.isEmpty else { return [] }

        let sortedByMemory = snapshots.sorted { $0.usedMemory > $1.usedMemory }
        let topCount = min(5, snapshots.count / 10) // Top 10% or 5, whichever is smaller

        return Array(sortedByMemory.prefix(topCount)).map { $0.timestamp }
    }

    private func calculateGrowthRate(_ snapshots: [MemorySnapshot]) -> Double {
        guard snapshots.count >= 2 else { return 0 }

        let firstSnapshot = snapshots.first!
        let lastSnapshot = snapshots.last!
        let duration = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)

        guard duration > 0 else { return 0 }

        let memoryGrowth = lastSnapshot.usedMemory - firstSnapshot.usedMemory
        return Double(memoryGrowth) / duration // bytes per second
    }

    private func calculateFragmentationRatio(_ allocations: [AllocationInfo]) -> Double {
        guard !allocations.isEmpty else { return 0 }

        let activeAllocations = allocations.filter { $0.isActive }
        guard !activeAllocations.isEmpty else { return 0 }

        // Simple fragmentation estimate based on allocation patterns
        let totalSize = activeAllocations.reduce(0) { $0 + $1.currentSize }
        let averageSize = totalSize / Int64(activeAllocations.count)

        var fragmentation = 0.0
        for allocation in activeAllocations {
            let deviation = abs(Double(allocation.currentSize - averageSize)) / Double(averageSize)
            fragmentation += deviation
        }

        return fragmentation / Double(activeAllocations.count)
    }
}

// MARK: - Analysis Result Types

/// Memory usage pattern analysis
struct MemoryUsagePattern {
    let trend: MemoryTrend
    let volatility: Double
    let peakTimes: [Date]
    let averageGrowthRate: Double
}

/// Memory usage trends
enum MemoryTrend {
    case decreasing
    case stable
    case increasing
    case rapidlyIncreasing
}

/// Allocation pattern analysis
struct AllocationPattern {
    let totalAllocations: Int
    let activeAllocations: Int
    let totalSize: Int64
    let averageSize: Int64
    let largestAllocation: AllocationInfo?
    let fragmentationRatio: Double
}

/// Memory anomaly detection
struct MemoryAnomaly {
    let timestamp: Date
    let type: AnomalyType
    let severity: AnomalySeverity
    let memoryValue: Int64
    let expectedValue: Int64

    enum AnomalyType {
        case spike
        case suddenDrop
        case leak
    }

    enum AnomalySeverity {
        case low
        case medium
        case high
    }
}
