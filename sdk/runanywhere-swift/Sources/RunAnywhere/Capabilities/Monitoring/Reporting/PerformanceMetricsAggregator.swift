//
//  MetricsAggregator.swift
//  RunAnywhere SDK
//
//  Aggregates performance metrics
//

import Foundation

/// Aggregates and summarizes performance metrics
internal class MetricsAggregator {
    private let logger = SDKLogger(category: "MetricsAggregator")

    /// Aggregate generation summaries
    func aggregateGenerations(_ summaries: [GenerationSummary]) -> AggregatedMetrics {
        guard !summaries.isEmpty else {
            return AggregatedMetrics()
        }

        // Group by framework
        let byFramework = Dictionary(grouping: summaries) { $0.framework }
        var frameworkMetrics: [LLMFramework: FrameworkMetrics] = [:]

        for (framework, frameworkSummaries) in byFramework {
            let metrics = calculateFrameworkMetrics(frameworkSummaries)
            frameworkMetrics[framework] = metrics
        }

        // Calculate overall metrics
        let totalTime = summaries.map { $0.totalTime }.reduce(0, +)
        let totalTokens = summaries.map { $0.tokenCount }.reduce(0, +)
        let avgTokensPerSecond = totalTime > 0 ? Double(totalTokens) / totalTime : 0

        return AggregatedMetrics(
            totalGenerations: summaries.count,
            totalTokens: totalTokens,
            totalTime: totalTime,
            averageTokensPerSecond: avgTokensPerSecond,
            frameworkMetrics: frameworkMetrics
        )
    }

    /// Calculate metrics for a specific framework
    private func calculateFrameworkMetrics(_ summaries: [GenerationSummary]) -> FrameworkMetrics {
        let totalTime = summaries.map { $0.totalTime }.reduce(0, +)
        let totalTokens = summaries.map { $0.tokenCount }.reduce(0, +)
        let avgTokensPerSecond = totalTime > 0 ? Double(totalTokens) / totalTime : 0

        let timeToFirstTokens = summaries.map { $0.timeToFirstToken }
        let avgTimeToFirstToken = timeToFirstTokens.reduce(0, +) / Double(timeToFirstTokens.count)

        let memoryUsages = summaries.map { $0.memoryUsed }
        let avgMemoryUsed = memoryUsages.reduce(0, +) / Int64(memoryUsages.count)

        return FrameworkMetrics(
            generationCount: summaries.count,
            totalTokens: totalTokens,
            averageTokensPerSecond: avgTokensPerSecond,
            averageTimeToFirstToken: avgTimeToFirstToken,
            averageMemoryUsed: avgMemoryUsed
        )
    }
}

/// Aggregated performance metrics
internal struct AggregatedMetrics {
    let totalGenerations: Int
    let totalTokens: Int
    let totalTime: TimeInterval
    let averageTokensPerSecond: Double
    let frameworkMetrics: [LLMFramework: FrameworkMetrics]

    init(
        totalGenerations: Int = 0,
        totalTokens: Int = 0,
        totalTime: TimeInterval = 0,
        averageTokensPerSecond: Double = 0,
        frameworkMetrics: [LLMFramework: FrameworkMetrics] = [:]
    ) {
        self.totalGenerations = totalGenerations
        self.totalTokens = totalTokens
        self.totalTime = totalTime
        self.averageTokensPerSecond = averageTokensPerSecond
        self.frameworkMetrics = frameworkMetrics
    }
}

/// Framework-specific metrics
internal struct FrameworkMetrics {
    let generationCount: Int
    let totalTokens: Int
    let averageTokensPerSecond: Double
    let averageTimeToFirstToken: TimeInterval
    let averageMemoryUsed: Int64
}
