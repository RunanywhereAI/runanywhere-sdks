//
//  PerformanceSnapshot.swift
//  RunAnywhere SDK
//
//  Performance snapshot at a point in time
//

import Foundation

/// Performance snapshot at a point in time
public struct PerformanceSnapshot: Codable {
    /// Timestamp when this snapshot was taken
    public let timestamp: Date

    /// Memory usage in bytes at this time
    public let memoryUsage: Int64

    /// CPU usage percentage (0.0 - 1.0)
    public let cpuUsage: Double

    /// Active framework at this time (if any)
    public let activeFramework: LLMFramework?

    public init(
        timestamp: Date,
        memoryUsage: Int64,
        cpuUsage: Double,
        activeFramework: LLMFramework? = nil
    ) {
        self.timestamp = timestamp
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.activeFramework = activeFramework
    }
}
