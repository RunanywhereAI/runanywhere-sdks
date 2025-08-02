//
//  ResultAnalyzer.swift
//  RunAnywhere SDK
//
//  Analyzes A/B test results
//

import Foundation

/// Analyzes A/B test results
public class ResultAnalyzer: TestAnalyzer {
    // MARK: - Properties

    private let statisticalEngine: StatisticalEngine
    private let winnerDeterminer: WinnerDeterminer

    // MARK: - Initialization

    public init(
        statisticalEngine: StatisticalEngine? = nil,
        winnerDeterminer: WinnerDeterminer? = nil
    ) {
        self.statisticalEngine = statisticalEngine ?? StatisticalEngine()
        self.winnerDeterminer = winnerDeterminer ?? WinnerDeterminer()
    }

    // MARK: - Public Methods

    /// Generate results for a test
    public func generateResults(test: ABTest, metrics: TestMetrics) -> ABTestResults {
        let variantAMetrics = metrics.variantMetrics[test.variantA.id] ?? []
        let variantBMetrics = metrics.variantMetrics[test.variantB.id] ?? []

        let performanceComparison = comparePerformance(
            variantA: variantAMetrics,
            variantB: variantBMetrics
        )

        let winner = determineWinner(
            comparison: performanceComparison,
            configuration: test.configuration
        )

        return ABTestResults(
            test: test,
            variantAMetrics: variantAMetrics,
            variantBMetrics: variantBMetrics,
            performanceComparison: performanceComparison,
            winner: winner,
            completedAt: test.completedAt ?? Date(),
            totalSamples: metrics.totalSamples
        )
    }

    // MARK: - TestAnalyzer Implementation

    public func calculateSignificance(
        variantAMetrics: [Double],
        variantBMetrics: [Double],
        confidenceLevel: Double = 0.95
    ) -> StatisticalSignificance {
        statisticalEngine.calculateSignificance(
            variantAMetrics: variantAMetrics,
            variantBMetrics: variantBMetrics,
            confidenceLevel: confidenceLevel
        )
    }

    public func comparePerformance(
        variantA: [ABTestMetric],
        variantB: [ABTestMetric]
    ) -> PerformanceComparison {
        let metricsCollector = TestMetricsCollector()

        // Extract metrics by type
        let tpsA = metricsCollector.extractMetricsByType(variantA, type: .tokensPerSecond)
        let tpsB = metricsCollector.extractMetricsByType(variantB, type: .tokensPerSecond)

        let ttftA = metricsCollector.extractMetricsByType(variantA, type: .timeToFirstToken)
        let ttftB = metricsCollector.extractMetricsByType(variantB, type: .timeToFirstToken)

        // Calculate statistics
        let tpsSignificance = calculateSignificance(
            variantAMetrics: tpsA,
            variantBMetrics: tpsB
        )

        let ttftSignificance = calculateSignificance(
            variantAMetrics: ttftA,
            variantBMetrics: ttftB
        )

        return PerformanceComparison(
            tokensPerSecond: MetricComparison(
                variantAMean: statisticalEngine.average(tpsA),
                variantBMean: statisticalEngine.average(tpsB),
                improvement: calculateImprovement(
                    baseline: statisticalEngine.average(tpsA),
                    variant: statisticalEngine.average(tpsB),
                    lowerIsBetter: false
                ),
                significance: tpsSignificance
            ),
            timeToFirstToken: MetricComparison(
                variantAMean: statisticalEngine.average(ttftA),
                variantBMean: statisticalEngine.average(ttftB),
                improvement: calculateImprovement(
                    baseline: statisticalEngine.average(ttftA),
                    variant: statisticalEngine.average(ttftB),
                    lowerIsBetter: true
                ),
                significance: ttftSignificance
            )
        )
    }

    public func determineWinner(
        comparison: PerformanceComparison,
        configuration: ABTestConfiguration
    ) -> TestVariant? {
        winnerDeterminer.determineWinner(
            comparison: comparison,
            configuration: configuration
        )
    }

    public func calculateImprovement(
        baseline: Double,
        variant: Double,
        lowerIsBetter: Bool = false
    ) -> Double {
        guard baseline != 0 else { return 0 }
        let improvement = ((variant - baseline) / baseline) * 100
        return lowerIsBetter ? -improvement : improvement
    }
}
