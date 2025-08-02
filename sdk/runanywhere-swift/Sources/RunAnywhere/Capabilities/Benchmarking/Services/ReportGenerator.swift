//
//  ReportGenerator.swift
//  RunAnywhere SDK
//
//  Generates comprehensive benchmark reports
//

import Foundation

/// Generates benchmark reports
public class ReportGenerator {
    // MARK: - Properties

    private let performanceMonitor = RealtimePerformanceMonitor.shared
    private let metricsAggregator = MetricsAggregator()
    private let statisticsCalculator = StatisticsCalculator()

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Generate comprehensive benchmark report
    public func generateReport(
        results: [BenchmarkResult],
        options: BenchmarkOptions
    ) -> BenchmarkReport {
        let performanceReport = performanceMonitor.generateReport()
        let summary = generateSummary(from: results)

        return BenchmarkReport(
            id: UUID(),
            timestamp: Date(),
            options: options,
            results: results,
            performanceReport: performanceReport,
            summary: summary
        )
    }

    /// Generate summary from results
    public func generateSummary(from results: [BenchmarkResult]) -> BenchmarkSummary {
        let serviceSummaries = metricsAggregator.aggregateServiceSummaries(results: results)
        let sorted = serviceSummaries.sorted { $0.averageTokensPerSecond > $1.averageTokensPerSecond }

        let fastestService = sorted.first?.serviceName
        let mostEfficientService = serviceSummaries.min {
            $0.averageMemoryUsage < $1.averageMemoryUsage
        }?.serviceName

        let overallSuccessRate = statisticsCalculator.average(
            serviceSummaries.map { $0.successRate }
        )

        return BenchmarkSummary(
            serviceSummaries: sorted,
            fastestService: fastestService,
            mostEfficientService: mostEfficientService,
            overallSuccessRate: overallSuccessRate
        )
    }
}
