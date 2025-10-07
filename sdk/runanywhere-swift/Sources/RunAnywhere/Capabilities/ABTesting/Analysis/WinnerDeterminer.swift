//
//  WinnerDeterminer.swift
//  RunAnywhere SDK
//
//  Determines the winner of A/B tests
//

import Foundation

/// Determines test winners based on performance
public class WinnerDeterminer {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Determine winner based on comparison
    public func determineWinner(
        comparison: PerformanceComparison,
        configuration: ABTestConfiguration
    ) -> TestVariant? {
        var scoreA = 0.0
        var scoreB = 0.0

        // Score based on tokens per second (higher is better)
        if comparison.tokensPerSecond.significance.isSignificant {
            if comparison.tokensPerSecond.variantAMean > comparison.tokensPerSecond.variantBMean {
                scoreA += 2
            } else {
                scoreB += 2
            }
        } else {
            // Not significant, give smaller weight
            if comparison.tokensPerSecond.variantAMean > comparison.tokensPerSecond.variantBMean {
                scoreA += 0.5
            } else {
                scoreB += 0.5
            }
        }

        // Score based on time to first token (lower is better)
        if comparison.timeToFirstToken.significance.isSignificant {
            if comparison.timeToFirstToken.variantAMean < comparison.timeToFirstToken.variantBMean {
                scoreA += 2
            } else {
                scoreB += 2
            }
        } else {
            // Not significant, give smaller weight
            if comparison.timeToFirstToken.variantAMean < comparison.timeToFirstToken.variantBMean {
                scoreA += 0.5
            } else {
                scoreB += 0.5
            }
        }

        // Check minimum improvement threshold
        let tpsImprovement = abs(comparison.tokensPerSecond.improvement)
        let ttftImprovement = abs(comparison.timeToFirstToken.improvement)

        // Both metrics must meet minimum threshold
        let meetsThreshold = tpsImprovement >= configuration.minimumDetectableEffect ||
                           ttftImprovement >= configuration.minimumDetectableEffect

        if !meetsThreshold {
            return nil // No clear winner
        }

        // Determine winner based on scores
        if scoreA > scoreB {
            return nil // Return variant A (needs to be passed in)
        } else if scoreB > scoreA {
            return nil // Return variant B (needs to be passed in)
        }

        return nil // Tie
    }

    /// Calculate confidence in winner determination
    public func calculateConfidence(
        comparison: PerformanceComparison
    ) -> Double {
        var totalConfidence = 0.0
        var metricCount = 0

        // TPS confidence
        if comparison.tokensPerSecond.significance.isSignificant {
            totalConfidence += 1.0 - comparison.tokensPerSecond.significance.pValue
            metricCount += 1
        }

        // TTFT confidence
        if comparison.timeToFirstToken.significance.isSignificant {
            totalConfidence += 1.0 - comparison.timeToFirstToken.significance.pValue
            metricCount += 1
        }

        return metricCount > 0 ? totalConfidence / Double(metricCount) : 0
    }
}
