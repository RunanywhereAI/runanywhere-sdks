//
//  CSVExporter.swift
//  RunAnywhere SDK
//
//  Exports benchmark results as CSV
//

import Foundation

/// CSV exporter for benchmark results
public class CSVExporter: BenchmarkExporter {
    // MARK: - Properties

    public let format: BenchmarkExportFormat = .csv

    // MARK: - Initialization

    public init() {}

    // MARK: - BenchmarkExporter Implementation

    public func export(results: [BenchmarkResult]) throws -> Data {
        let csv = generateCSV(from: results)
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.dataConversionFailed
        }
        return data
    }

    public func export(report: BenchmarkReport) throws -> Data {
        let csv = generateCSV(from: report.results)
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.dataConversionFailed
        }
        return data
    }

    // MARK: - Private Methods

    private func generateCSV(from results: [BenchmarkResult]) -> String {
        var csv = "Service,Framework,Prompt,Category,Avg Time,Avg TTFT,Avg TPS,Min TPS,Max TPS,StdDev TPS,Avg Memory,Iterations,Error\n"

        for result in results {
            csv += "\"\(result.serviceName)\","
            csv += "\"\(result.framework?.rawValue ?? "unknown")\","
            csv += "\"\(result.promptId)\","
            csv += "\"\(result.promptCategory.rawValue)\","
            csv += "\(String(format: "%.3f", result.avgTotalTime)),"
            csv += "\(String(format: "%.3f", result.avgTimeToFirstToken)),"
            csv += "\(String(format: "%.2f", result.avgTokensPerSecond)),"
            csv += "\(String(format: "%.2f", result.minTokensPerSecond)),"
            csv += "\(String(format: "%.2f", result.maxTokensPerSecond)),"
            csv += "\(String(format: "%.2f", result.stdDevTokensPerSecond)),"
            csv += "\(result.avgMemoryUsed),"
            csv += "\(result.iterationCount),"
            csv += "\"\(result.error ?? "")\"\n"
        }

        return csv
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .dataConversionFailed:
            return "Failed to convert export data"
        }
    }
}
