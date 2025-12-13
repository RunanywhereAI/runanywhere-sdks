//
//  TTSEvent.swift
//  RunAnywhere SDK
//
//  TTS-specific analytics event and types
//

import Foundation

// MARK: - TTS Event Type

/// TTS event types
public enum TTSEventType: String {
    case synthesisStarted = "tts_synthesis_started"
    case synthesisCompleted = "tts_synthesis_completed"
    case synthesisChunk = "tts_synthesis_chunk"
    case modelLoaded = "tts_model_loaded"
    case modelLoadFailed = "tts_model_load_failed"
    case error = "tts_error"
}

// MARK: - TTS Event

/// TTS-specific analytics event
public struct TTSEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: TTSEventType,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}

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
