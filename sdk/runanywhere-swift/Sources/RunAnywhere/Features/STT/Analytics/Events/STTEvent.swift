//
//  STTEvent.swift
//  RunAnywhere SDK
//
//  STT-specific analytics event and types
//

import Foundation

// MARK: - STT Event Type

/// STT event types
public enum STTEventType: String {
    case transcriptionStarted = "stt_transcription_started"
    case transcriptionCompleted = "stt_transcription_completed"
    case partialTranscript = "stt_partial_transcript"
    case finalTranscript = "stt_final_transcript"
    case speakerDetected = "stt_speaker_detected"
    case speakerChanged = "stt_speaker_changed"
    case languageDetected = "stt_language_detected"
    case modelLoaded = "stt_model_loaded"
    case modelLoadFailed = "stt_model_load_failed"
    case error = "stt_error"
}

// MARK: - STT Event

/// STT-specific analytics event
public struct STTEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: STTEventType,
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

// MARK: - STT Metrics

/// STT-specific metrics
public struct STTMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int
    public let averageConfidence: Float
    public let averageLatency: TimeInterval

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalTranscriptions = 0
        self.averageConfidence = 0
        self.averageLatency = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalTranscriptions: Int,
        averageConfidence: Float,
        averageLatency: TimeInterval
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalTranscriptions = totalTranscriptions
        self.averageConfidence = averageConfidence
        self.averageLatency = averageLatency
    }
}
