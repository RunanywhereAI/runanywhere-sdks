//
//  SignificanceCalculator.swift
//  RunAnywhere SDK
//
//  Calculates statistical significance for A/B tests
//

import Foundation

/// Calculates statistical significance
public class SignificanceCalculator {
    // MARK: - Properties

    private let statisticalEngine: StatisticalEngine

    // MARK: - Initialization

    public init(statisticalEngine: StatisticalEngine = StatisticalEngine()) {
        self.statisticalEngine = statisticalEngine
    }

    // MARK: - Public Methods

    /// Calculate significance for a metric
    public func calculateSignificance(
        metricA: [Double],
        metricB: [Double],
        confidenceLevel: Double = 0.95
    ) -> StatisticalSignificance {
        statisticalEngine.calculateSignificance(
            variantAMetrics: metricA,
            variantBMetrics: metricB,
            confidenceLevel: confidenceLevel
        )
    }

    /// Calculate sample size needed for desired power
    public func calculateSampleSize(
        baselineRate: Double,
        minimumDetectableEffect: Double,
        confidenceLevel: Double = 0.95,
        power: Double = 0.8
    ) -> Int {
        // Z-scores for confidence level and power
        let zAlpha = getZScore(for: confidenceLevel)
        let zBeta = getZScore(for: power)

        // Expected conversion rate with MDE
        let expectedRate = baselineRate * (1 + minimumDetectableEffect / 100)

        // Pooled standard deviation
        let pooledRate = (baselineRate + expectedRate) / 2
        let pooledStdDev = sqrt(2 * pooledRate * (1 - pooledRate))

        // Sample size calculation
        let numerator = pow(zAlpha * pooledStdDev + zBeta * sqrt(
            baselineRate * (1 - baselineRate) + expectedRate * (1 - expectedRate)
        ), 2)
        let denominator = pow(expectedRate - baselineRate, 2)

        let sampleSize = denominator > 0 ? numerator / denominator : 1000
        return Int(ceil(sampleSize))
    }

    /// Check if results are statistically significant
    public func isSignificant(
        pValue: Double,
        confidenceLevel: Double = 0.95
    ) -> Bool {
        pValue < (1 - confidenceLevel)
    }

    // MARK: - Private Methods

    private func getZScore(for probability: Double) -> Double {
        // Simplified z-score lookup
        // In production, use proper inverse normal CDF
        switch probability {
        case 0.99:
            return 2.576
        case 0.95:
            return 1.96
        case 0.90:
            return 1.645
        case 0.80:
            return 1.282
        default:
            return 1.96
        }
    }
}
