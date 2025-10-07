//
//  ExporterFactory.swift
//  RunAnywhere SDK
//
//  Factory for creating benchmark exporters
//

import Foundation

/// Factory for creating benchmark exporters
public class ExporterFactory {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Create exporter for specified format
    public func createExporter(for format: BenchmarkExportFormat) -> BenchmarkExporter {
        switch format {
        case .json:
            return JSONExporter()
        case .csv:
            return CSVExporter()
        case .markdown:
            return MarkdownExporter()
        }
    }

    /// Export results in specified format
    public func export(
        results: [BenchmarkResult],
        format: BenchmarkExportFormat
    ) throws -> Data {
        let exporter = createExporter(for: format)
        return try exporter.export(results: results)
    }

    /// Export report in specified format
    public func export(
        report: BenchmarkReport,
        format: BenchmarkExportFormat
    ) throws -> Data {
        let exporter = createExporter(for: format)
        return try exporter.export(report: report)
    }
}
