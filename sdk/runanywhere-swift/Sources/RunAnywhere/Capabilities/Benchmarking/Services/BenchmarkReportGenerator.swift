//
//  ReportGenerator.swift
//  RunAnywhere SDK
//
//  Generates comprehensive benchmark reports
//

import Foundation

/// Generates benchmark reports
public class BenchmarkReportGenerator {
    // MARK: - Properties

    private let performanceMonitor: PerformanceMonitor
    private let metricsAggregator = BenchmarkMetricsAggregator()
    private let statisticsCalculator = StatisticsCalculator()

    // MARK: - Initialization

    public init(performanceMonitor: PerformanceMonitor) {
        self.performanceMonitor = performanceMonitor
    }

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
