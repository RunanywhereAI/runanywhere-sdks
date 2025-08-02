//
//  MetricsAggregator.swift
//  RunAnywhere SDK
//
//  Aggregates benchmark metrics
//

import Foundation

/// Aggregates benchmark metrics from multiple runs
public class BenchmarkMetricsAggregator {
    // MARK: - Properties

    private let statisticsCalculator = StatisticsCalculator()

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Aggregate results from multiple runs
    public func aggregate(
        _ results: [SingleRunResult],
        serviceName: String,
        prompt: BenchmarkPrompt
    ) -> BenchmarkResult {
        guard !results.isEmpty else {
            return createEmptyResult(serviceName: serviceName, prompt: prompt)
        }

        let totalTimes = results.map { $0.totalTime }
        let ttftTimes = results.map { $0.timeToFirstToken }
        let tpsSpeeds = results.map { $0.tokensPerSecond }
        let memoryUsages = results.map { Double($0.memoryUsed) }

        return BenchmarkResult(
            serviceName: serviceName,
            framework: results.first?.framework,
            promptId: prompt.id,
            promptCategory: prompt.category,
            avgTotalTime: statisticsCalculator.average(totalTimes),
            avgTimeToFirstToken: statisticsCalculator.average(ttftTimes),
            avgTokensPerSecond: statisticsCalculator.average(tpsSpeeds),
            minTokensPerSecond: tpsSpeeds.min() ?? 0,
            maxTokensPerSecond: tpsSpeeds.max() ?? 0,
            stdDevTokensPerSecond: statisticsCalculator.standardDeviation(tpsSpeeds),
            avgMemoryUsed: Int64(statisticsCalculator.average(memoryUsages)),
            iterationCount: results.count
        )
    }

    /// Aggregate service summaries
    public func aggregateServiceSummaries(
        results: [BenchmarkResult]
    ) -> [ServiceSummary] {
        let groupedByService = Dictionary(grouping: results) { $0.serviceName }

        return groupedByService.compactMap { (service, serviceResults) in
            guard !serviceResults.isEmpty else { return nil }

            let avgSpeed = statisticsCalculator.average(
                serviceResults.map { $0.avgTokensPerSecond }
            )
            let avgMemory = Int64(statisticsCalculator.average(
                serviceResults.map { Double($0.avgMemoryUsed) }
            ))
            let successRate = Double(serviceResults.filter { $0.error == nil }.count) /
                             Double(serviceResults.count)

            return ServiceSummary(
                serviceName: service,
                framework: serviceResults.first?.framework,
                averageTokensPerSecond: avgSpeed,
                averageMemoryUsage: avgMemory,
                successRate: successRate,
                testCount: serviceResults.count
            )
        }
    }

    // MARK: - Private Methods

    private func createEmptyResult(
        serviceName: String,
        prompt: BenchmarkPrompt
    ) -> BenchmarkResult {
        BenchmarkResult(
            serviceName: serviceName,
            promptId: prompt.id,
            promptCategory: prompt.category,
            error: "No results to aggregate"
        )
    }
}
