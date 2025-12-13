//
//  SpeakerDiarizationEvent.swift
//  RunAnywhere SDK
//
//  Speaker diarization analytics event and types
//

import Foundation

// MARK: - Speaker Diarization Event Type

/// Speaker diarization event types
public enum SpeakerDiarizationEventType: String {
    case sessionStarted = "speaker_diarization_session_started"
    case sessionCompleted = "speaker_diarization_session_completed"
    case speakerDetected = "speaker_diarization_speaker_detected"
    case speakerChanged = "speaker_diarization_speaker_changed"
    case error = "speaker_diarization_error"
}

// MARK: - Speaker Diarization Event

/// Speaker diarization analytics event
public struct SpeakerDiarizationEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: SpeakerDiarizationEventType,
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

// MARK: - Speaker Diarization Metrics

/// Speaker diarization metrics
public struct SpeakerDiarizationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSessions: Int
    public let totalSpeakersDetected: Int
    public let averageProcessingTimeMs: Double

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalSessions = 0
        self.totalSpeakersDetected = 0
        self.averageProcessingTimeMs = 0
    }

    internal init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalSessions: Int,
        totalSpeakersDetected: Int,
        averageProcessingTimeMs: Double
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSessions = totalSessions
        self.totalSpeakersDetected = totalSpeakersDetected
        self.averageProcessingTimeMs = averageProcessingTimeMs
    }
}
