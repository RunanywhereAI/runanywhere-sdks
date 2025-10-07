//
//  BenchmarkSummary.swift
//  RunAnywhere SDK
//
//  Overall benchmark summary
//

import Foundation

/// Overall benchmark summary
public struct BenchmarkSummary: Codable {
    public let serviceSummaries: [ServiceSummary]
    public let fastestService: String?
    public let mostEfficientService: String?
    public let overallSuccessRate: Double
}
