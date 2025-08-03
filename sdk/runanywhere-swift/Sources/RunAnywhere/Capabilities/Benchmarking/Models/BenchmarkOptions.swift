//
//  BenchmarkOptions.swift
//  RunAnywhere SDK
//
//  Benchmark configuration options
//

import Foundation

/// Benchmark configuration options
public struct BenchmarkOptions: Codable {
    public let iterations: Int
    public let includeWarmup: Bool
    public let measureMemory: Bool
    public let measurePerformance: Bool

    public init(
        iterations: Int = 3,
        includeWarmup: Bool = true,
        measureMemory: Bool = true,
        measurePerformance: Bool = true
    ) {
        self.iterations = iterations
        self.includeWarmup = includeWarmup
        self.measureMemory = measureMemory
        self.measurePerformance = measurePerformance
    }

    public static let `default` = BenchmarkOptions()
}

/// Export format options
public enum BenchmarkExportFormat {
    case json
    case csv
    case markdown
}
