//
//  StatisticalEngine.swift
//  RunAnywhere SDK
//
//  Statistical calculations for A/B testing
//

import Foundation

/// Performs statistical calculations
public class StatisticalEngine {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Calculate statistical significance
    public func calculateSignificance(
        variantAMetrics: [Double],
        variantBMetrics: [Double],
        confidenceLevel: Double = 0.95
    ) -> StatisticalSignificance {
        guard !variantAMetrics.isEmpty && !variantBMetrics.isEmpty else {
            return StatisticalSignificance(
                pValue: 1.0,
                isSignificant: false,
                confidenceLevel: confidenceLevel,
                effectSize: 0
            )
        }

        // Calculate means
        let meanA = average(variantAMetrics)
        let meanB = average(variantBMetrics)

        // Calculate variances
        let varianceA = variance(variantAMetrics, mean: meanA)
        let varianceB = variance(variantBMetrics, mean: meanB)

        // Calculate t-statistic (Welch's t-test)
        let standardError = sqrt(
            varianceA / Double(variantAMetrics.count) +
            varianceB / Double(variantBMetrics.count)
        )

        guard standardError > 0 else {
            return StatisticalSignificance(
                pValue: 1.0,
                isSignificant: false,
                confidenceLevel: confidenceLevel,
                effectSize: 0
            )
        }

        let tStatistic = abs(meanA - meanB) / standardError

        // Calculate degrees of freedom (Welch-Satterthwaite equation)
        let df = calculateDegreesOfFreedom(
            varianceA: varianceA,
            countA: variantAMetrics.count,
            varianceB: varianceB,
            countB: variantBMetrics.count
        )

        // Calculate p-value (simplified - would use proper t-distribution in production)
        let pValue = calculatePValue(tStatistic: tStatistic, degreesOfFreedom: df)

        // Calculate effect size (Cohen's d)
        let pooledStdDev = sqrt((varianceA + varianceB) / 2)
        let effectSize = pooledStdDev > 0 ? abs(meanA - meanB) / pooledStdDev : 0

        return StatisticalSignificance(
            pValue: pValue,
            isSignificant: pValue < (1 - confidenceLevel),
            confidenceLevel: confidenceLevel,
            effectSize: effectSize
        )
    }

    /// Calculate average
    public func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Calculate variance
    public func variance(_ values: [Double], mean: Double? = nil) -> Double {
        guard values.count > 1 else { return 0 }

        let m = mean ?? average(values)
        let squaredDiffs = values.map { pow($0 - m, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count - 1)
    }

    /// Calculate standard deviation
    public func standardDeviation(_ values: [Double]) -> Double {
        sqrt(variance(values))
    }

    // MARK: - Private Methods

    private func calculateDegreesOfFreedom(
        varianceA: Double,
        countA: Int,
        varianceB: Double,
        countB: Int
    ) -> Double {
        let s1 = varianceA / Double(countA)
        let s2 = varianceB / Double(countB)

        let numerator = pow(s1 + s2, 2)
        let denominator = pow(s1, 2) / Double(countA - 1) +
                         pow(s2, 2) / Double(countB - 1)

        return denominator > 0 ? numerator / denominator : Double(countA + countB - 2)
    }

    private func calculatePValue(tStatistic: Double, degreesOfFreedom: Double) -> Double {
        // Simplified p-value calculation using normal approximation
        // In production, use proper t-distribution
        let z = tStatistic
        let pValue = 2 * (1 - normalCDF(z))
        return max(0, min(1, pValue))
    }

    private func normalCDF(_ z: Double) -> Double {
        // Approximation of normal CDF using error function
        return 0.5 * (1 + erf(z / sqrt(2)))
    }
}
