//
//  TrendAnalyzer.swift
//  RunAnywhere SDK
//
//  Analyzes memory usage trends over time
//

import Foundation

/// Analyzes memory usage trends and predicts future usage
class TrendAnalyzer {
    private let logger = SDKLogger(category: "TrendAnalyzer")

    /// Analyze memory trends from snapshots
    func analyzeTrends(snapshots: [MemorySnapshot]) -> TrendAnalysis {
        guard snapshots.count >= 2 else {
            return TrendAnalysis(
                trend: .stable,
                growthRate: 0,
                acceleration: 0,
                predictedUsage: nil,
                timeToLimit: nil
            )
        }

        let trend = calculateTrend(snapshots)
        let growthRate = calculateGrowthRate(snapshots)
        let acceleration = calculateAcceleration(snapshots)
        let prediction = predictFutureUsage(snapshots, growthRate: growthRate)
        let timeToLimit = calculateTimeToMemoryLimit(
            current: snapshots.last!.usedMemory,
            growthRate: growthRate
        )

        return TrendAnalysis(
            trend: trend,
            growthRate: growthRate,
            acceleration: acceleration,
            predictedUsage: prediction,
            timeToLimit: timeToLimit
        )
    }

    /// Perform regression analysis on memory usage
    func performRegression(snapshots: [MemorySnapshot]) -> RegressionResult? {
        guard snapshots.count >= 3 else { return nil }

        // Convert to time series data
        let startTime = snapshots.first!.timestamp
        let data: [(x: Double, y: Double)] = snapshots.map { snapshot in
            let x = snapshot.timestamp.timeIntervalSince(startTime)
            let y = Double(snapshot.usedMemory)
            return (x, y)
        }

        // Calculate linear regression
        let regression = linearRegression(data)

        // Calculate R-squared
        let rSquared = calculateRSquared(data: data, slope: regression.slope, intercept: regression.intercept)

        return RegressionResult(
            slope: regression.slope,
            intercept: regression.intercept,
            rSquared: rSquared,
            isSignificant: rSquared > 0.7
        )
    }

    /// Identify cyclic patterns in memory usage
    func identifyCycles(snapshots: [MemorySnapshot]) -> CycleAnalysis? {
        guard snapshots.count >= 20 else { return nil }

        let memoryValues = snapshots.map { Double($0.usedMemory) }

        // Simple cycle detection using autocorrelation
        let cycles = detectCycles(in: memoryValues)

        guard !cycles.isEmpty else { return nil }

        let primaryCycle = cycles.first!
        return CycleAnalysis(
            hasCycle: true,
            period: primaryCycle.period,
            amplitude: primaryCycle.amplitude,
            confidence: primaryCycle.confidence
        )
    }

    // MARK: - Private Methods

    private func calculateTrend(_ snapshots: [MemorySnapshot]) -> MemoryTrend {
        let firstQuarter = snapshots.prefix(snapshots.count / 4)
        let lastQuarter = snapshots.suffix(snapshots.count / 4)

        let earlyAverage = firstQuarter.reduce(0) { $0 + $1.usedMemory } / Int64(firstQuarter.count)
        let lateAverage = lastQuarter.reduce(0) { $0 + $1.usedMemory } / Int64(lastQuarter.count)

        let percentChange = Double(lateAverage - earlyAverage) / Double(earlyAverage) * 100

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

    private func calculateGrowthRate(_ snapshots: [MemorySnapshot]) -> Double {
        guard snapshots.count >= 2 else { return 0 }

        let first = snapshots.first!
        let last = snapshots.last!
        let duration = last.timestamp.timeIntervalSince(first.timestamp)

        guard duration > 0 else { return 0 }

        let growth = last.usedMemory - first.usedMemory
        return Double(growth) / duration // bytes per second
    }

    private func calculateAcceleration(_ snapshots: [MemorySnapshot]) -> Double {
        guard snapshots.count >= 3 else { return 0 }

        let midPoint = snapshots.count / 2
        let firstHalf = Array(snapshots.prefix(midPoint))
        let secondHalf = Array(snapshots.suffix(snapshots.count - midPoint))

        let firstRate = calculateGrowthRate(firstHalf)
        let secondRate = calculateGrowthRate(secondHalf)

        return secondRate - firstRate
    }

    private func predictFutureUsage(_ snapshots: [MemorySnapshot], growthRate: Double) -> PredictedUsage? {
        guard let lastSnapshot = snapshots.last, growthRate != 0 else { return nil }

        let in5Minutes = lastSnapshot.usedMemory + Int64(growthRate * 300)
        let in10Minutes = lastSnapshot.usedMemory + Int64(growthRate * 600)
        let in30Minutes = lastSnapshot.usedMemory + Int64(growthRate * 1800)

        return PredictedUsage(
            in5Minutes: max(0, in5Minutes),
            in10Minutes: max(0, in10Minutes),
            in30Minutes: max(0, in30Minutes),
            confidence: calculatePredictionConfidence(snapshots)
        )
    }

    private func calculateTimeToMemoryLimit(current: Int64, growthRate: Double) -> TimeInterval? {
        guard growthRate > 0 else { return nil }

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryLimit = Int64(Double(totalMemory) * 0.9) // 90% threshold
        let remainingMemory = memoryLimit - current

        guard remainingMemory > 0 else { return 0 }

        return Double(remainingMemory) / growthRate
    }

    private func calculatePredictionConfidence(_ snapshots: [MemorySnapshot]) -> Double {
        guard let regression = performRegression(snapshots: snapshots) else { return 0 }
        return regression.rSquared
    }

    private func linearRegression(_ data: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double) {
        let n = Double(data.count)
        let sumX = data.reduce(0) { $0 + $1.x }
        let sumY = data.reduce(0) { $0 + $1.y }
        let sumXY = data.reduce(0) { $0 + ($1.x * $1.y) }
        let sumXX = data.reduce(0) { $0 + ($1.x * $1.x) }

        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n

        return (slope, intercept)
    }

    private func calculateRSquared(data: [(x: Double, y: Double)], slope: Double, intercept: Double) -> Double {
        let meanY = data.reduce(0) { $0 + $1.y } / Double(data.count)

        var ssTotal: Double = 0
        var ssResidual: Double = 0

        for point in data {
            let predicted = slope * point.x + intercept
            ssTotal += pow(point.y - meanY, 2)
            ssResidual += pow(point.y - predicted, 2)
        }

        return 1 - (ssResidual / ssTotal)
    }

    private func detectCycles(in values: [Double]) -> [DetectedCycle] {
        // Simplified cycle detection
        // In production, would use FFT or more sophisticated methods
        var cycles: [DetectedCycle] = []

        // Check for common periods (in number of samples)
        let commonPeriods = [10, 20, 30, 60] // Corresponding to various time intervals

        for period in commonPeriods {
            if let cycle = checkForCycle(values: values, period: period) {
                cycles.append(cycle)
            }
        }

        return cycles.sorted { $0.confidence > $1.confidence }
    }

    private func checkForCycle(values: [Double], period: Int) -> DetectedCycle? {
        guard values.count >= period * 2 else { return nil }

        var correlation: Double = 0
        var count = 0

        for i in 0..<(values.count - period) {
            correlation += values[i] * values[i + period]
            count += 1
        }

        correlation /= Double(count)

        // Normalize
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)

        guard variance > 0 else { return nil }

        let normalizedCorrelation = correlation / variance

        if normalizedCorrelation > 0.5 {
            let amplitude = values.max()! - values.min()!
            return DetectedCycle(
                period: TimeInterval(period) * 0.5, // Assuming 0.5s snapshot interval
                amplitude: amplitude,
                confidence: normalizedCorrelation
            )
        }

        return nil
    }
}

// MARK: - Analysis Result Types

/// Trend analysis results
struct TrendAnalysis {
    let trend: MemoryTrend
    let growthRate: Double // bytes per second
    let acceleration: Double // change in growth rate
    let predictedUsage: PredictedUsage?
    let timeToLimit: TimeInterval? // seconds until memory limit
}

/// Predicted memory usage
struct PredictedUsage {
    let in5Minutes: Int64
    let in10Minutes: Int64
    let in30Minutes: Int64
    let confidence: Double // 0-1
}

/// Regression analysis results
struct RegressionResult {
    let slope: Double
    let intercept: Double
    let rSquared: Double
    let isSignificant: Bool
}

/// Cycle analysis results
struct CycleAnalysis {
    let hasCycle: Bool
    let period: TimeInterval?
    let amplitude: Double?
    let confidence: Double
}

/// Detected memory usage cycle
struct DetectedCycle {
    let period: TimeInterval
    let amplitude: Double
    let confidence: Double
}
