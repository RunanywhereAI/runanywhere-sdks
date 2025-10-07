//
//  StatisticsCalculator.swift
//  RunAnywhere SDK
//
//  Calculates statistical metrics for benchmarks
//

import Foundation

/// Calculates statistical metrics
public class StatisticsCalculator {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Calculate average of values
    public func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Calculate standard deviation
    public func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }

        let avg = average(values)
        let squaredDiffs = values.map { pow($0 - avg, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count - 1)

        return sqrt(variance)
    }

    /// Calculate median
    public func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }

    /// Calculate percentile
    public func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty, percentile >= 0, percentile <= 100 else { return 0 }

        let sorted = values.sorted()
        let index = Double(sorted.count - 1) * (percentile / 100)
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        let weight = index - Double(lower)

        if upper >= sorted.count {
            return sorted[lower]
        }

        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
