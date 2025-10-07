//
//  FragmentationDetector.swift
//  RunAnywhere SDK
//
//  Detects memory fragmentation issues
//

import Foundation

/// Detects memory fragmentation issues
class FragmentationDetector {
    private let logger = SDKLogger(category: "FragmentationDetector")

    /// Detect fragmentation from allocations and system metrics
    func detectFragmentation(
        allocations: [AllocationInfo],
        systemStats: MemoryStats
    ) -> FragmentationAnalysis {
        let allocationFragmentation = analyzeAllocationFragmentation(allocations)
        let systemFragmentation = analyzeSystemFragmentation(systemStats)
        let overallScore = calculateOverallScore(
            allocationScore: allocationFragmentation.score,
            systemScore: systemFragmentation
        )

        return FragmentationAnalysis(
            score: overallScore,
            severity: severityFromScore(overallScore),
            allocationFragmentation: allocationFragmentation,
            recommendations: generateRecommendations(score: overallScore)
        )
    }

    /// Analyze fragmentation from allocation patterns
    private func analyzeAllocationFragmentation(_ allocations: [AllocationInfo]) -> AllocationFragmentation {
        guard !allocations.isEmpty else {
            return AllocationFragmentation(
                score: 0,
                smallAllocations: 0,
                largeAllocations: 0,
                averageGap: 0
            )
        }

        let activeAllocations = allocations.filter { $0.isActive }
        guard !activeAllocations.isEmpty else {
            return AllocationFragmentation(
                score: 0,
                smallAllocations: 0,
                largeAllocations: 0,
                averageGap: 0
            )
        }

        // Categorize allocations by size
        let smallThreshold: Int64 = 1024 * 1024 // 1MB
        let largeThreshold: Int64 = 10 * 1024 * 1024 // 10MB

        let smallAllocations = activeAllocations.filter { $0.currentSize < smallThreshold }.count
        let largeAllocations = activeAllocations.filter { $0.currentSize > largeThreshold }.count

        // Calculate fragmentation score based on allocation patterns
        let totalAllocations = activeAllocations.count
        let smallRatio = Double(smallAllocations) / Double(totalAllocations)
        let mixedSizeScore = calculateMixedSizeScore(allocations: activeAllocations)

        let fragmentationScore = (smallRatio * 0.4) + (mixedSizeScore * 0.6)

        return AllocationFragmentation(
            score: fragmentationScore,
            smallAllocations: smallAllocations,
            largeAllocations: largeAllocations,
            averageGap: calculateAverageGap(allocations: activeAllocations)
        )
    }

    /// Analyze system-level fragmentation
    private func analyzeSystemFragmentation(_ stats: MemoryStats) -> Double {
        // Use memory pressure as a proxy for fragmentation
        switch stats.pressure {
        case .normal:
            return 0.0
        case .warning:
            return 0.3
        case .urgent:
            return 0.6
        case .critical:
            return 0.9
        }
    }

    /// Calculate mixed size score (higher = more fragmented)
    private func calculateMixedSizeScore(allocations: [AllocationInfo]) -> Double {
        guard allocations.count > 1 else { return 0 }

        let sizes = allocations.map { $0.currentSize }.sorted()
        var variance: Double = 0
        let mean = Double(sizes.reduce(0, +)) / Double(sizes.count)

        for size in sizes {
            let diff = Double(size) - mean
            variance += diff * diff
        }

        variance /= Double(sizes.count)
        let stdDev = sqrt(variance)

        // Normalize to 0-1 range
        let coefficientOfVariation = mean > 0 ? stdDev / mean : 0
        return min(coefficientOfVariation, 1.0)
    }

    /// Calculate average gap between allocations
    private func calculateAverageGap(allocations: [AllocationInfo]) -> Int64 {
        guard allocations.count > 1 else { return 0 }

        // This is a simplified calculation
        // In a real implementation, we would need actual memory addresses
        let totalSize = allocations.reduce(0) { $0 + $1.currentSize }
        let averageSize = totalSize / Int64(allocations.count)

        // Estimate gaps based on allocation patterns
        return averageSize / 10 // Rough estimate
    }

    /// Calculate overall fragmentation score
    private func calculateOverallScore(allocationScore: Double, systemScore: Double) -> Double {
        // Weighted average favoring allocation patterns
        return (allocationScore * 0.7) + (systemScore * 0.3)
    }

    /// Determine severity from score
    private func severityFromScore(_ score: Double) -> FragmentationSeverity {
        switch score {
        case 0..<0.3:
            return .low
        case 0.3..<0.6:
            return .moderate
        case 0.6..<0.8:
            return .high
        default:
            return .critical
        }
    }

    /// Generate recommendations based on fragmentation score
    private func generateRecommendations(score: Double) -> [String] {
        var recommendations: [String] = []

        if score > 0.3 {
            recommendations.append("Consider consolidating small allocations")
        }

        if score > 0.5 {
            recommendations.append("Memory compaction may improve performance")
            recommendations.append("Review allocation patterns for optimization opportunities")
        }

        if score > 0.7 {
            recommendations.append("High fragmentation detected - consider restarting the app")
            recommendations.append("Implement memory pooling for frequent allocations")
        }

        return recommendations
    }
}

// MARK: - Analysis Result Types

/// Fragmentation analysis results
struct FragmentationAnalysis {
    let score: Double // 0-1, higher = more fragmented
    let severity: FragmentationSeverity
    let allocationFragmentation: AllocationFragmentation
    let recommendations: [String]
}

/// Fragmentation severity levels
enum FragmentationSeverity {
    case low
    case moderate
    case high
    case critical
}

/// Allocation-based fragmentation metrics
struct AllocationFragmentation {
    let score: Double
    let smallAllocations: Int
    let largeAllocations: Int
    let averageGap: Int64
}
