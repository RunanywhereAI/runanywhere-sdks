//
//  TestAnalyzer.swift
//  RunAnywhere SDK
//
//  Protocol for A/B test analysis
//

import Foundation

/// Protocol for analyzing A/B test results
public protocol TestAnalyzer {
    /// Calculate statistical significance
    func calculateSignificance(
        variantAMetrics: [Double],
        variantBMetrics: [Double],
        confidenceLevel: Double
    ) -> StatisticalSignificance

    /// Compare performance between variants
    func comparePerformance(
        variantA: [ABTestMetric],
        variantB: [ABTestMetric]
    ) -> PerformanceComparison

    /// Determine test winner
    func determineWinner(
        comparison: PerformanceComparison,
        configuration: ABTestConfiguration
    ) -> TestVariant?

    /// Calculate improvement percentage
    func calculateImprovement(
        baseline: Double,
        variant: Double,
        lowerIsBetter: Bool
    ) -> Double
}
