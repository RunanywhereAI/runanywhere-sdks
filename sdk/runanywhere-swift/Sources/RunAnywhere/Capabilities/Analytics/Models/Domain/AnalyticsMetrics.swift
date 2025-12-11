//
//  AnalyticsMetrics.swift
//  RunAnywhere SDK
//
//  Base protocol and common metrics for analytics
//

import Foundation

// MARK: - Metrics System

/// Base protocol for analytics metrics
/// All capability-specific metrics must conform to this protocol
public protocol AnalyticsMetrics: Sendable {
    /// Total number of events tracked
    var totalEvents: Int { get }

    /// When metrics collection started
    var startTime: Date { get }

    /// When the last event was tracked
    var lastEventTime: Date? { get }
}

// MARK: - Common Metrics Implementation

/// Common analytics metrics aggregation
public struct CommonAnalyticsMetrics: AnalyticsMetrics, Sendable {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let eventCounts: [String: Int]
    public let errorCount: Int
    public let successRate: Double

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        eventCounts: [String: Int] = [:],
        errorCount: Int = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.eventCounts = eventCounts
        self.errorCount = errorCount
        self.successRate = totalEvents > 0 ? Double(totalEvents - errorCount) / Double(totalEvents) : 1.0
    }
}
