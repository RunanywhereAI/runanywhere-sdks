//
//  LeakDetector.swift
//  RunAnywhere SDK
//
//  Detects potential memory leaks
//

import Foundation

/// Detects potential memory leaks in active allocations
class LeakDetector {
    private let logger = SDKLogger(category: "LeakDetector")

    // Leak detection thresholds
    private let minimumDuration: TimeInterval = 10.0 // 10 seconds
    private let growthRateThreshold: Double = 1_000_000 // 1MB/sec
    private let minimumSize: Int64 = 10_485_760 // 10MB

    /// Detect potential memory leaks from active allocations
    func detectLeaks(from allocations: [String: AllocationInfo]) -> [MemoryLeak] {
        var detectedLeaks: [MemoryLeak] = []

        for (id, allocation) in allocations {
            guard allocation.isActive else { continue }

            let duration = allocation.duration
            guard duration >= minimumDuration else { continue }

            let growth = allocation.currentSize - allocation.initialSize
            let growthRate = Double(growth) / duration

            // Check for continuous growth pattern
            if growthRate > growthRateThreshold || allocation.currentSize > minimumSize {
                detectedLeaks.append(
                    MemoryLeak(
                        id: id,
                        name: allocation.name,
                        initialSize: allocation.initialSize,
                        currentSize: allocation.currentSize,
                        growthRate: growthRate,
                        duration: duration
                    )
                )

                logger.warning("Potential leak detected: \(allocation.name), growth rate: \(Int(growthRate)) bytes/sec")
            }
        }

        return detectedLeaks
    }

    /// Analyze leak patterns
    func analyzeLeakPatterns(_ leaks: [MemoryLeak]) -> LeakAnalysis {
        guard !leaks.isEmpty else {
            return LeakAnalysis(
                totalLeaks: 0,
                totalMemoryLeaked: 0,
                averageGrowthRate: 0,
                criticalLeaks: []
            )
        }

        let totalMemory = leaks.reduce(0) { $0 + $1.currentSize }
        let averageGrowth = leaks.reduce(0.0) { $0 + $1.growthRate } / Double(leaks.count)
        let criticalLeaks = leaks.filter { $0.growthRate > growthRateThreshold * 2 }

        return LeakAnalysis(
            totalLeaks: leaks.count,
            totalMemoryLeaked: totalMemory,
            averageGrowthRate: averageGrowth,
            criticalLeaks: criticalLeaks
        )
    }
}

/// Leak analysis results
struct LeakAnalysis {
    let totalLeaks: Int
    let totalMemoryLeaked: Int64
    let averageGrowthRate: Double
    let criticalLeaks: [MemoryLeak]
}
