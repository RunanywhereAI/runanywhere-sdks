//
//  PerformanceComparison.swift
//  RunAnywhere SDK
//
//  Performance comparison between variants
//

import Foundation

/// Performance comparison
public struct PerformanceComparison {
    public let tokensPerSecond: MetricComparison
    public let timeToFirstToken: MetricComparison
}

/// Metric comparison
public struct MetricComparison {
    public let variantAMean: Double
    public let variantBMean: Double
    public let improvement: Double // Percentage
    public let significance: StatisticalSignificance
}
