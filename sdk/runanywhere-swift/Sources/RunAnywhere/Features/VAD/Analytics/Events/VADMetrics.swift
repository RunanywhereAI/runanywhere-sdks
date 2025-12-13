//
//  VADMetrics.swift
//  RunAnywhere SDK
//
//  VAD analytics metrics structure
//

import Foundation

// MARK: - VAD Metrics

/// VAD-specific metrics
public struct VADMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalDetections: Int
    public let averageEnergyLevel: Float
    public let totalSpeechFrames: Int
    public let totalSilenceFrames: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalDetections = 0
        self.averageEnergyLevel = 0
        self.totalSpeechFrames = 0
        self.totalSilenceFrames = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalDetections: Int,
        averageEnergyLevel: Float,
        totalSpeechFrames: Int,
        totalSilenceFrames: Int
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalDetections = totalDetections
        self.averageEnergyLevel = averageEnergyLevel
        self.totalSpeechFrames = totalSpeechFrames
        self.totalSilenceFrames = totalSilenceFrames
    }
}
