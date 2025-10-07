//
//  ABTestResults.swift
//  RunAnywhere SDK
//
//  A/B test results
//

import Foundation

/// Test results
public struct ABTestResults {
    public let test: ABTest
    public let variantAMetrics: [ABTestMetric]
    public let variantBMetrics: [ABTestMetric]
    public let performanceComparison: PerformanceComparison
    public let winner: TestVariant?
    public let completedAt: Date
    public let totalSamples: Int
}
