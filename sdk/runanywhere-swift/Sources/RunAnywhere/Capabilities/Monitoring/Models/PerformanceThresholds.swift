//
//  PerformanceThresholds.swift
//  RunAnywhere SDK
//
//  Performance thresholds configuration
//

import Foundation

/// Performance thresholds configuration
public struct PerformanceThresholds {
    /// Maximum allowed memory usage ratio (0.0 - 1.0)
    public let maxMemoryUsage: Double

    /// Minimum acceptable tokens per second
    public let minTokensPerSecond: Double

    /// Maximum acceptable latency to first token
    public let maxLatency: TimeInterval

    /// Maximum allowed CPU usage ratio (0.0 - 1.0)
    public let maxCPUUsage: Double

    /// Default thresholds
    public static let `default` = PerformanceThresholds(
        maxMemoryUsage: 0.8,
        minTokensPerSecond: 10.0,
        maxLatency: 5.0,
        maxCPUUsage: 0.9
    )

    public init(
        maxMemoryUsage: Double,
        minTokensPerSecond: Double,
        maxLatency: TimeInterval,
        maxCPUUsage: Double
    ) {
        self.maxMemoryUsage = maxMemoryUsage
        self.minTokensPerSecond = minTokensPerSecond
        self.maxLatency = maxLatency
        self.maxCPUUsage = maxCPUUsage
    }
}
