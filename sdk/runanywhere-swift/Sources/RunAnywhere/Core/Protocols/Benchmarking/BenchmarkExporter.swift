//
//  BenchmarkExporter.swift
//  RunAnywhere SDK
//
//  Protocol for benchmark result export
//

import Foundation

/// Protocol for exporting benchmark results
public protocol BenchmarkExporter {
    /// Export format type
    var format: BenchmarkExportFormat { get }

    /// Export benchmark results
    func export(results: [BenchmarkResult]) throws -> Data

    /// Export complete benchmark report
    func export(report: BenchmarkReport) throws -> Data
}

/// Base exporter with common functionality
public protocol BaseExporter: BenchmarkExporter {
    /// Format header for export
    func formatHeader() -> String

    /// Format a single result
    func formatResult(_ result: BenchmarkResult) -> String

    /// Format footer for export
    func formatFooter() -> String
}
