//
//  TTSMetrics.swift
//  RunAnywhere SDK
//
//  TTS-specific metrics model
//

import Foundation

// MARK: - TTS Metrics

/// TTS-specific metrics
public struct TTSMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSyntheses: Int
    public let averageCharactersPerSecond: Double
    public let averageProcessingTimeMs: Double
    public let totalCharactersProcessed: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalSyntheses = 0
        self.averageCharactersPerSecond = 0
        self.averageProcessingTimeMs = 0
        self.totalCharactersProcessed = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalSyntheses: Int,
        averageCharactersPerSecond: Double,
        averageProcessingTimeMs: Double,
        totalCharactersProcessed: Int
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSyntheses = totalSyntheses
        self.averageCharactersPerSecond = averageCharactersPerSecond
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.totalCharactersProcessed = totalCharactersProcessed
    }
}
