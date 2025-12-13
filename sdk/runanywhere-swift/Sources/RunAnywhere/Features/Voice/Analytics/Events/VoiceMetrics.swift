//
//  VoiceMetrics.swift
//  RunAnywhere SDK
//
//  Voice-specific analytics metrics
//

import Foundation

// MARK: - Voice Metrics

/// Voice-specific metrics
public struct VoiceMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int
    public let totalPipelineExecutions: Int
    public let averageTranscriptionDuration: TimeInterval
    public let averagePipelineDuration: TimeInterval
    public let averageRealTimeFactor: Double

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalTranscriptions = 0
        self.totalPipelineExecutions = 0
        self.averageTranscriptionDuration = 0
        self.averagePipelineDuration = 0
        self.averageRealTimeFactor = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalTranscriptions: Int,
        totalPipelineExecutions: Int,
        averageTranscriptionDuration: TimeInterval,
        averagePipelineDuration: TimeInterval,
        averageRealTimeFactor: Double
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalTranscriptions = totalTranscriptions
        self.totalPipelineExecutions = totalPipelineExecutions
        self.averageTranscriptionDuration = averageTranscriptionDuration
        self.averagePipelineDuration = averagePipelineDuration
        self.averageRealTimeFactor = averageRealTimeFactor
    }

}
