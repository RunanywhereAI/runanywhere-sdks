//
//  TelemetryParams.swift
//  RunAnywhere SDK
//
//  Input parameter structs for telemetry tracking methods
//

import Foundation

// MARK: - Generation Parameters

/// Parameters for tracking generation start events
public struct GenerationStartParams: Sendable {
    public let generationId: String
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let promptTokens: Int
    public let maxTokens: Int
    public let device: String
    public let osVersion: String

    public init(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        promptTokens: Int,
        maxTokens: Int,
        device: String,
        osVersion: String
    ) {
        self.generationId = generationId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.promptTokens = promptTokens
        self.maxTokens = maxTokens
        self.device = device
        self.osVersion = osVersion
    }
}

/// Parameters for tracking generation completion events
public struct GenerationCompletedParams: Sendable {
    public let generationId: String
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTimeMs: Double
    public let timeToFirstTokenMs: Double
    public let tokensPerSecond: Double
    public let device: String
    public let osVersion: String

    public init(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        inputTokens: Int,
        outputTokens: Int,
        totalTimeMs: Double,
        timeToFirstTokenMs: Double,
        tokensPerSecond: Double,
        device: String,
        osVersion: String
    ) {
        self.generationId = generationId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTimeMs = totalTimeMs
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.tokensPerSecond = tokensPerSecond
        self.device = device
        self.osVersion = osVersion
    }
}

/// Parameters for tracking generation failure events
public struct GenerationFailedParams: Sendable {
    public let generationId: String
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let inputTokens: Int
    public let totalTimeMs: Double
    public let errorMessage: String
    public let device: String
    public let osVersion: String

    public init(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        inputTokens: Int,
        totalTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) {
        self.generationId = generationId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.inputTokens = inputTokens
        self.totalTimeMs = totalTimeMs
        self.errorMessage = errorMessage
        self.device = device
        self.osVersion = osVersion
    }
}

// MARK: - STT Parameters

/// Parameters for tracking STT model load events
public struct STTModelLoadParams: Sendable {
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let loadTimeMs: Double
    public let modelSizeBytes: Int64?
    public let device: String
    public let osVersion: String
    public let success: Bool
    public let errorMessage: String?

    public init(
        modelId: String,
        modelName: String,
        framework: String,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.loadTimeMs = loadTimeMs
        self.modelSizeBytes = modelSizeBytes
        self.device = device
        self.osVersion = osVersion
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Parameters for tracking STT transcription events
public struct STTTranscriptionParams: Sendable {
    public let transcriptionId: String
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let audioDurationMs: Double
    public let transcriptionTimeMs: Double
    public let realTimeFactor: Double
    public let wordCount: Int
    public let confidence: Double?
    public let device: String
    public let osVersion: String
    public let success: Bool
    public let errorMessage: String?

    public init(
        transcriptionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        audioDurationMs: Double,
        transcriptionTimeMs: Double,
        realTimeFactor: Double,
        wordCount: Int,
        confidence: Double? = nil,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.transcriptionId = transcriptionId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.audioDurationMs = audioDurationMs
        self.transcriptionTimeMs = transcriptionTimeMs
        self.realTimeFactor = realTimeFactor
        self.wordCount = wordCount
        self.confidence = confidence
        self.device = device
        self.osVersion = osVersion
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - TTS Parameters

/// Parameters for tracking TTS synthesis events
public struct TTSSynthesisParams: Sendable {
    public let synthesisId: String
    public let modelId: String
    public let modelName: String
    public let framework: String
    public let textLength: Int
    public let audioDurationMs: Double
    public let synthesisTimeMs: Double
    public let realTimeFactor: Double
    public let device: String
    public let osVersion: String
    public let success: Bool
    public let errorMessage: String?

    public init(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        textLength: Int,
        audioDurationMs: Double,
        synthesisTimeMs: Double,
        realTimeFactor: Double,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.synthesisId = synthesisId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.textLength = textLength
        self.audioDurationMs = audioDurationMs
        self.synthesisTimeMs = synthesisTimeMs
        self.realTimeFactor = realTimeFactor
        self.device = device
        self.osVersion = osVersion
        self.success = success
        self.errorMessage = errorMessage
    }
}
