//
//  LiveMetrics.swift
//  RunAnywhere SDK
//
//  Live performance metrics model
//

import Foundation

/// Live performance metrics
public struct LiveMetrics {
    /// Current memory usage in bytes
    public var memoryUsage: Int64 = 0

    /// Available memory in bytes
    public var availableMemory: Int64 = 0

    /// CPU usage percentage (0.0 - 1.0)
    public var cpuUsage: Double = 0

    /// Current thermal state
    public var thermalState: ProcessInfo.ThermalState = .nominal

    /// Current tokens per second rate
    public var currentTokensPerSecond: Double = 0

    /// Time to first token in current generation
    public var timeToFirstToken: TimeInterval = 0

    public init() {}
}
