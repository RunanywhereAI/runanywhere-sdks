//
//  PerformanceReport.swift
//  RunAnywhere SDK
//
//  Performance report model
//

import Foundation

/// Performance report for a time range
public struct PerformanceReport: Codable {
    /// Time range covered by this report (in seconds)
    public let timeRange: TimeInterval

    /// Average memory usage during the period
    public let averageMemoryUsage: Int64

    /// Peak memory usage during the period
    public let peakMemoryUsage: Int64

    /// Average CPU usage during the period
    public let averageCPUUsage: Double

    /// Peak CPU usage during the period
    public let peakCPUUsage: Double

    /// Number of alerts during the period
    public let alertCount: Int

    /// Performance snapshots within this period
    public let snapshots: [PerformanceSnapshot]

    public init(
        timeRange: TimeInterval,
        averageMemoryUsage: Int64,
        peakMemoryUsage: Int64,
        averageCPUUsage: Double,
        peakCPUUsage: Double,
        alertCount: Int,
        snapshots: [PerformanceSnapshot]
    ) {
        self.timeRange = timeRange
        self.averageMemoryUsage = averageMemoryUsage
        self.peakMemoryUsage = peakMemoryUsage
        self.averageCPUUsage = averageCPUUsage
        self.peakCPUUsage = peakCPUUsage
        self.alertCount = alertCount
        self.snapshots = snapshots
    }
}
