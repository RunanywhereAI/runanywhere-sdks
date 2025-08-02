//
//  BenchmarkMetricsCollector.swift
//  RunAnywhere SDK
//
//  Protocol for collecting benchmark metrics
//

import Foundation

/// Protocol for collecting benchmark metrics
public protocol BenchmarkMetricsCollector {
    /// Start collecting metrics for a benchmark run
    func beginCollection(serviceName: String, promptId: String)

    /// Record time to first token
    func recordTimeToFirstToken(_ time: TimeInterval)

    /// Record token generation
    func recordToken(_ token: String)

    /// Record memory usage
    func recordMemoryUsage(_ bytes: Int64)

    /// Finalize metrics collection
    func endCollection() -> SingleRunResult?

    /// Reset metrics collector
    func reset()
}
