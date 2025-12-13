//
//  TTSEventData.swift
//  RunAnywhere SDK
//
//  TTS-specific analytics event data models
//

import Foundation

// MARK: - TTS Event Data Models

/// TTS synthesis start event data
public struct TTSSynthesisStartData: AnalyticsEventData {
    public let characterCount: Int
    public let voice: String
    public let language: String
    public let startTimestamp: TimeInterval

    public init(characterCount: Int, voice: String, language: String) {
        self.characterCount = characterCount
        self.voice = voice
        self.language = language
        self.startTimestamp = Date().timeIntervalSince1970
    }
}

/// TTS synthesis completion event data
public struct TTSSynthesisCompletionData: AnalyticsEventData {
    public let characterCount: Int
    public let audioDurationMs: Double
    public let audioSizeBytes: Int
    public let processingTimeMs: Double
    public let charactersPerSecond: Double
    public let realTimeFactor: Double

    public init(
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingTimeMs: Double
    ) {
        self.characterCount = characterCount
        self.audioDurationMs = audioDurationMs
        self.audioSizeBytes = audioSizeBytes
        self.processingTimeMs = processingTimeMs
        self.charactersPerSecond = processingTimeMs > 0 ? Double(characterCount) / (processingTimeMs / 1000.0) : 0
        self.realTimeFactor = audioDurationMs > 0 ? processingTimeMs / audioDurationMs : 0
    }
}

/// TTS synthesis completion event data with full telemetry fields for backend
public struct TTSSynthesisTelemetryData: AnalyticsEventData {
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

    // TTS-specific fields
    public let characterCount: Int?
    public let charactersPerSecond: Double?
    public let audioSizeBytes: Int?
    public let sampleRate: Int?
    public let voice: String?
    public let outputDurationMs: Double?

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
        characterCount: Int?,
        charactersPerSecond: Double?,
        audioSizeBytes: Int?,
        sampleRate: Int?,
        voice: String?,
        outputDurationMs: Double?
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
        self.characterCount = characterCount
        self.charactersPerSecond = charactersPerSecond
        self.audioSizeBytes = audioSizeBytes
        self.sampleRate = sampleRate
        self.voice = voice
        self.outputDurationMs = outputDurationMs
    }
}

/// TTS synthesis failure event data
public struct TTSSynthesisFailureData: AnalyticsEventData {
    public let synthesisId: String
    public let characterCount: Int
    public let processingTimeMs: Double
    public let errorMessage: String

    public init(
        synthesisId: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String
    ) {
        self.synthesisId = synthesisId
        self.characterCount = characterCount
        self.processingTimeMs = processingTimeMs
        self.errorMessage = errorMessage
    }
}

/// TTS model loading event data
public struct TTSModelLoadingData: AnalyticsEventData {
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
