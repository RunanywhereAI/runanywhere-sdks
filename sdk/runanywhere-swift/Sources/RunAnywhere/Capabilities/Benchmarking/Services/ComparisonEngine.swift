//
//  ComparisonEngine.swift
//  RunAnywhere SDK
//
//  Compares benchmark results between services
//

import Foundation

/// Engine for comparing benchmark results
public class ComparisonEngine {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Compare two benchmark results
    public func compare(
        result1: SingleRunResult,
        service1Name: String,
        result2: SingleRunResult,
        service2Name: String
    ) -> ComparisonResult {
        let winner = determineWinner(result1: result1, result2: result2)

        return ComparisonResult(
            service1Name: service1Name,
            service2Name: service2Name,
            result1: result1,
            result2: result2,
            winner: winner == 1 ? service1Name : service2Name
        )
    }

    /// Compare multiple services
    public func compareMultiple(
        results: [String: SingleRunResult]
    ) -> [(service: String, rank: Int, score: Double)] {
        var rankings: [(service: String, score: Double)] = []

        for (service, result) in results {
            let score = calculateScore(result)
            rankings.append((service, score))
        }

        // Sort by score (higher is better)
        rankings.sort { $0.score > $1.score }

        // Assign ranks
        return rankings.enumerated().map { index, item in
            (service: item.service, rank: index + 1, score: item.score)
        }
    }

    // MARK: - Private Methods

    private func determineWinner(
        result1: SingleRunResult,
        result2: SingleRunResult
    ) -> Int {
        // Primary metric: tokens per second
        if result1.tokensPerSecond > result2.tokensPerSecond * 1.1 {
            return 1
        } else if result2.tokensPerSecond > result1.tokensPerSecond * 1.1 {
            return 2
        }

        // Secondary metric: time to first token
        if result1.timeToFirstToken < result2.timeToFirstToken * 0.9 {
            return 1
        } else if result2.timeToFirstToken < result1.timeToFirstToken * 0.9 {
            return 2
        }

        // Tertiary metric: memory usage
        if result1.memoryUsed < result2.memoryUsed * 0.8 {
            return 1
        } else if result2.memoryUsed < result1.memoryUsed * 0.8 {
            return 2
        }

        // Default to result1 if very close
        return 1
    }

    private func calculateScore(_ result: SingleRunResult) -> Double {
        // Weighted scoring:
        // - Tokens per second: 50%
        // - Time to first token: 30%
        // - Memory efficiency: 20%

        let tpsScore = result.tokensPerSecond
        let ttftScore = 1.0 / (result.timeToFirstToken + 0.001) * 10 // Inverse, scaled
        let memoryScore = 1.0 / (Double(result.memoryUsed) / 1_000_000 + 1) * 100 // MB, inverse

        return (tpsScore * 0.5) + (ttftScore * 0.3) + (memoryScore * 0.2)
    }
}
