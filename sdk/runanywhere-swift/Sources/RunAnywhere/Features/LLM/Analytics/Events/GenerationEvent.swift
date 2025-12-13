//
//  GenerationEvent.swift
//  RunAnywhere SDK
//
//  Generation-specific analytics event and types
//

import Foundation

// MARK: - Generation Event Type

/// Generation event types
public enum GenerationEventType: String {
    case sessionStarted = "generation_session_started"
    case sessionEnded = "generation_session_ended"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case firstTokenGenerated = "generation_first_token"
    case streamingUpdate = "generation_streaming_update"
    case error = "generation_error"
    case modelLoaded = "generation_model_loaded"
    case modelLoadFailed = "generation_model_load_failed"
    case modelUnloaded = "generation_model_unloaded"
}

// MARK: - Generation Event

/// Generation-specific analytics event
public struct GenerationEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: GenerationEventType,
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
