//
//  JSONExporter.swift
//  RunAnywhere SDK
//
//  Exports benchmark results as JSON
//

import Foundation

/// JSON exporter for benchmark results
public class JSONExporter: BenchmarkExporter {
    // MARK: - Properties

    public let format: BenchmarkExportFormat = .json

    private let encoder: JSONEncoder

    // MARK: - Initialization

    public init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - BenchmarkExporter Implementation

    public func export(results: [BenchmarkResult]) throws -> Data {
        try encoder.encode(results)
    }

    public func export(report: BenchmarkReport) throws -> Data {
        try encoder.encode(report)
    }
}
