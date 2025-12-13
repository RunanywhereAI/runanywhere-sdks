//
//  VoiceEventData.swift
//  RunAnywhere SDK
//
//  Voice-specific analytics event data models
//

import Foundation

// MARK: - Voice Event Data Models

/// Pipeline creation event data
public struct PipelineCreationData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]

    public init(stageCount: Int, stages: [String]) {
        self.stageCount = stageCount
        self.stages = stages
    }

}

/// Pipeline started event data
public struct PipelineStartedData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]
    public let startTimestamp: TimeInterval

    public init(stageCount: Int, stages: [String], startTimestamp: TimeInterval) {
        self.stageCount = stageCount
        self.stages = stages
        self.startTimestamp = startTimestamp
    }

}

/// Pipeline completion event data
public struct PipelineCompletionData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]
    public let totalTimeMs: Double

    public init(stageCount: Int, stages: [String], totalTimeMs: Double) {
        self.stageCount = stageCount
        self.stages = stages
        self.totalTimeMs = totalTimeMs
    }

}

/// Stage execution event data
public struct StageExecutionData: AnalyticsEventData {
    public let stageName: String
    public let durationMs: Double

    public init(stageName: String, durationMs: Double) {
        self.stageName = stageName
        self.durationMs = durationMs
    }

}

/// Voice transcription event data
public struct VoiceTranscriptionData: AnalyticsEventData {
    public let durationMs: Double
    public let wordCount: Int
    public let audioLengthMs: Double
    public let realTimeFactor: Double

    public init(durationMs: Double, wordCount: Int, audioLengthMs: Double, realTimeFactor: Double) {
        self.durationMs = durationMs
        self.wordCount = wordCount
        self.audioLengthMs = audioLengthMs
        self.realTimeFactor = realTimeFactor
    }

}

/// Transcription start event data
public struct TranscriptionStartData: AnalyticsEventData {
    public let audioLengthMs: Double
    public let startTimestamp: TimeInterval

    public init(audioLengthMs: Double, startTimestamp: TimeInterval) {
        self.audioLengthMs = audioLengthMs
        self.startTimestamp = startTimestamp
    }

}

/// Voice pipeline processing event data
public struct VoicePipelineEventData: AnalyticsEventData {
    public let eventType: VoiceEventType
    public let timestamp: Date
    public let sessionId: String?
    public let vadEnabled: Bool
    public let sttModelId: String?
    public let llmModelId: String?
    public let ttsEnabled: Bool
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?
    public let deviceInfo: TelemetryDeviceInfo

    public init(
        eventType: VoiceEventType,
        timestamp: Date,
        sessionId: String?,
        vadEnabled: Bool,
        sttModelId: String?,
        llmModelId: String?,
        ttsEnabled: Bool,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String?,
        deviceInfo: TelemetryDeviceInfo
    ) {
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.vadEnabled = vadEnabled
        self.sttModelId = sttModelId
        self.llmModelId = llmModelId
        self.ttsEnabled = ttsEnabled
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.deviceInfo = deviceInfo
    }

}
