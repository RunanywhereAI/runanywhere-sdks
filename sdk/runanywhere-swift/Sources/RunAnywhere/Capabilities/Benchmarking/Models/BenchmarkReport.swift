//
//  BenchmarkReport.swift
//  RunAnywhere SDK
//
//  Complete benchmark report
//

import Foundation

/// Complete benchmark report
public struct BenchmarkReport: Codable {
    public let id: UUID
    public let timestamp: Date
    public let options: BenchmarkOptions
    public let results: [BenchmarkResult]
    public let performanceReport: PerformanceReport
    public let summary: BenchmarkSummary
}
