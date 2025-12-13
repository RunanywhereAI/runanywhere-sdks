//
//  STTEventData.swift
//  RunAnywhere SDK
//
//  STT-specific analytics event data models
//

import Foundation

// MARK: - STT Event Data Models

/// STT transcription completion data
public struct STTTranscriptionData: AnalyticsEventData {
    public let wordCount: Int
    public let confidence: Float
    public let durationMs: Double
    public let audioLengthMs: Double
    public let realTimeFactor: Double
    public let speakerId: String

    public init(
        wordCount: Int,
        confidence: Float,
        durationMs: Double,
        audioLengthMs: Double,
        realTimeFactor: Double,
        speakerId: String = "unknown"
    ) {
        self.wordCount = wordCount
        self.confidence = confidence
        self.durationMs = durationMs
        self.audioLengthMs = audioLengthMs
        self.realTimeFactor = realTimeFactor
        self.speakerId = speakerId
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

/// Final transcript event data
public struct FinalTranscriptData: AnalyticsEventData {
    public let textLength: Int
    public let wordCount: Int
    public let confidence: Float
    public let speakerId: String
    public let timestamp: TimeInterval

    public init(
        textLength: Int,
        wordCount: Int,
        confidence: Float,
        speakerId: String = "unknown",
        timestamp: TimeInterval
    ) {
        self.textLength = textLength
        self.wordCount = wordCount
        self.confidence = confidence
        self.speakerId = speakerId
        self.timestamp = timestamp
    }
}

/// Partial transcript event data
public struct PartialTranscriptData: AnalyticsEventData {
    public let textLength: Int
    public let wordCount: Int

    public init(textLength: Int, wordCount: Int) {
        self.textLength = textLength
        self.wordCount = wordCount
    }
}

/// Speaker detection event data
public struct SpeakerDetectionData: AnalyticsEventData {
    public let speakerId: String
    public let confidence: Float
    public let timestamp: TimeInterval

    public init(speakerId: String, confidence: Float, timestamp: TimeInterval) {
        self.speakerId = speakerId
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// Speaker change event data
public struct SpeakerChangeData: AnalyticsEventData {
    public let fromSpeaker: String
    public let toSpeaker: String
    public let timestamp: TimeInterval

    public init(fromSpeaker: String?, toSpeaker: String, timestamp: TimeInterval) {
        self.fromSpeaker = fromSpeaker ?? "none"
        self.toSpeaker = toSpeaker
        self.timestamp = timestamp
    }
}

/// Language detection event data
public struct LanguageDetectionData: AnalyticsEventData {
    public let language: String
    public let confidence: Float

    public init(language: String, confidence: Float) {
        self.language = language
        self.confidence = confidence
    }
}

/// STT transcription completion event data with full telemetry fields for backend
public struct STTTranscriptionTelemetryData: AnalyticsEventData {
    // Model info
    public let modelId: String
    public let modelName: String?
    public let framework: String?

    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Common performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?
    public let errorCode: String?

    // STT-specific fields
    public let audioDurationMs: Double?
    public let realTimeFactor: Double?
    public let wordCount: Int?
    public let confidence: Double?
    public let language: String?
    public let isStreaming: Bool?
    public let segmentIndex: Int?

    public init(
        modelId: String,
        modelName: String?,
        framework: String?,
        device: String?,
        osVersion: String?,
        platform: String?,
        sdkVersion: String?,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        audioDurationMs: Double?,
        realTimeFactor: Double?,
        wordCount: Int?,
        confidence: Double?,
        language: String?,
        isStreaming: Bool? = false,
        segmentIndex: Int? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.audioDurationMs = audioDurationMs
        self.realTimeFactor = realTimeFactor
        self.wordCount = wordCount
        self.confidence = confidence
        self.language = language
        self.isStreaming = isStreaming
        self.segmentIndex = segmentIndex
    }
}

/// STT model loading event data
public struct STTModelLoadingData: AnalyticsEventData {
    public let modelId: String
    public let modelName: String?
    public let framework: String?
    public let loadTimeMs: Double
    public let modelSizeBytes: Int64?
    public let success: Bool
    public let errorMessage: String?

    public init(
        modelId: String,
        modelName: String? = nil,
        framework: String? = nil,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.loadTimeMs = loadTimeMs
        self.modelSizeBytes = modelSizeBytes
        self.success = success
        self.errorMessage = errorMessage
    }
}
