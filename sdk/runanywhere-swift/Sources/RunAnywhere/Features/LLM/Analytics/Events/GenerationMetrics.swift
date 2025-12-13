//
//  GenerationMetrics.swift
//  RunAnywhere SDK
//
//  Generation-specific metrics
//

import Foundation

// MARK: - Generation Metrics

/// Generation-specific metrics
public struct GenerationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalGenerations: Int
    public let averageTimeToFirstToken: TimeInterval
    public let averageTokensPerSecond: Double
    public let totalInputTokens: Int
    public let totalOutputTokens: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalGenerations = 0
        self.averageTimeToFirstToken = 0
        self.averageTokensPerSecond = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
    }

    internal init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalGenerations: Int,
        averageTimeToFirstToken: TimeInterval,
        averageTokensPerSecond: Double,
        totalInputTokens: Int,
        totalOutputTokens: Int
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalGenerations = totalGenerations
        self.averageTimeToFirstToken = averageTimeToFirstToken
        self.averageTokensPerSecond = averageTokensPerSecond
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}
