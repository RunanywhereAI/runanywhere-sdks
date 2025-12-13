//
//  SpeakerDiarizationEventData.swift
//  RunAnywhere SDK
//
//  Speaker diarization analytics event data models
//

import Foundation

// MARK: - Session Event Data

/// Session started event data
public struct DiarizationSessionStartData: AnalyticsEventData {
    public let maxSpeakers: Int
    public let startTimestamp: TimeInterval

    public init(maxSpeakers: Int) {
        self.maxSpeakers = maxSpeakers
        self.startTimestamp = Date().timeIntervalSince1970
    }
}

/// Session completed event data
public struct DiarizationSessionCompletionData: AnalyticsEventData {
    public let processingTimeMs: Double
    public let speakerCount: Int
    public let segmentCount: Int
    public let averageConfidence: Double
    public let maxSpeakers: Int
    public let success: Bool

    public init(
        processingTimeMs: Double,
        speakerCount: Int,
        segmentCount: Int,
        averageConfidence: Double,
        maxSpeakers: Int,
        success: Bool = true
    ) {
        self.processingTimeMs = processingTimeMs
        self.speakerCount = speakerCount
        self.segmentCount = segmentCount
        self.averageConfidence = averageConfidence
        self.maxSpeakers = maxSpeakers
        self.success = success
    }
}

/// Session failure event data
public struct DiarizationSessionFailureData: AnalyticsEventData {
    public let processingTimeMs: Double
    public let maxSpeakers: Int
    public let errorMessage: String

    public init(
        processingTimeMs: Double,
        maxSpeakers: Int,
        errorMessage: String
    ) {
        self.processingTimeMs = processingTimeMs
        self.maxSpeakers = maxSpeakers
        self.errorMessage = errorMessage
    }
}

// MARK: - Speaker Event Data

/// Speaker detected event data
public struct DiarizationSpeakerDetectedData: AnalyticsEventData {
    public let speakerId: String
    public let speakerIndex: Int
    public let confidence: Double
    public let timestamp: TimeInterval

    public init(
        speakerId: String,
        speakerIndex: Int,
        confidence: Double
    ) {
        self.speakerId = speakerId
        self.speakerIndex = speakerIndex
        self.confidence = confidence
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Speaker changed event data
public struct DiarizationSpeakerChangedData: AnalyticsEventData {
    public let fromSpeakerId: String?
    public let toSpeakerId: String
    public let timestamp: TimeInterval

    public init(
        fromSpeakerId: String?,
        toSpeakerId: String
    ) {
        self.fromSpeakerId = fromSpeakerId
        self.toSpeakerId = toSpeakerId
        self.timestamp = Date().timeIntervalSince1970
    }
}
