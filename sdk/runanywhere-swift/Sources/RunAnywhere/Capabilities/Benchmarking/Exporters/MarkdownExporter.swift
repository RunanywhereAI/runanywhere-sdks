//
//  MarkdownExporter.swift
//  RunAnywhere SDK
//
//  Exports benchmark results as Markdown
//

import Foundation

/// Markdown exporter for benchmark results
public class MarkdownExporter: BenchmarkExporter {
    // MARK: - Properties

    public let format: BenchmarkExportFormat = .markdown

    private let dateFormatter: DateFormatter

    // MARK: - Initialization

    public init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .medium
    }

    // MARK: - BenchmarkExporter Implementation

    public func export(results: [BenchmarkResult]) throws -> Data {
        let markdown = generateMarkdown(from: results)
        guard let data = markdown.data(using: .utf8) else {
            throw ExportError.dataConversionFailed
        }
        return data
    }

    public func export(report: BenchmarkReport) throws -> Data {
        let markdown = generateFullReport(from: report)
        guard let data = markdown.data(using: .utf8) else {
            throw ExportError.dataConversionFailed
        }
        return data
    }

    // MARK: - Private Methods

    private func generateMarkdown(from results: [BenchmarkResult]) -> String {
        var markdown = "# Benchmark Results\n\n"
        markdown += "Date: \(dateFormatter.string(from: Date()))\n\n"

        markdown += "## Results Table\n\n"
        markdown += "| Service | Framework | Prompt | Category | Avg TPS | Avg TTFT | Avg Memory |\n"
        markdown += "|---------|-----------|--------|----------|---------|----------|------------|\n"

        for result in results {
            markdown += "| \(result.serviceName) "
            markdown += "| \(result.framework?.rawValue ?? "N/A") "
            markdown += "| \(result.promptId) "
            markdown += "| \(result.promptCategory.rawValue) "
            markdown += "| \(String(format: "%.1f", result.avgTokensPerSecond)) "
            markdown += "| \(String(format: "%.2f", result.avgTimeToFirstToken))s "
            markdown += "| \(formatMemory(result.avgMemoryUsed)) |\n"
        }

        return markdown
    }

    private func generateFullReport(from report: BenchmarkReport) -> String {
        var markdown = "# Benchmark Report\n\n"
        markdown += "**Report ID**: `\(report.id)`\n"
        markdown += "**Date**: \(dateFormatter.string(from: report.timestamp))\n\n"

        // Summary section
        if let summary = report.summary as BenchmarkSummary? {
            markdown += "## Summary\n\n"
            if let fastest = summary.fastestService {
                markdown += "- **Fastest Service**: \(fastest)\n"
            }
            if let efficient = summary.mostEfficientService {
                markdown += "- **Most Memory Efficient**: \(efficient)\n"
            }
            markdown += "- **Overall Success Rate**: \(String(format: "%.1f", summary.overallSuccessRate * 100))%\n"
            markdown += "\n"
        }

        // Options section
        markdown += "## Test Configuration\n\n"
        markdown += "- **Iterations**: \(report.options.iterations)\n"
        markdown += "- **Warmup**: \(report.options.includeWarmup ? "Yes" : "No")\n"
        markdown += "- **Measure Memory**: \(report.options.measureMemory ? "Yes" : "No")\n"
        markdown += "- **Measure Performance**: \(report.options.measurePerformance ? "Yes" : "No")\n"
        markdown += "\n"

        // Results table
        markdown += generateMarkdown(from: report.results)

        return markdown
    }

    private func formatMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
