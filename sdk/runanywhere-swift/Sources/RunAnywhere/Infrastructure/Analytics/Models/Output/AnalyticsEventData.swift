// swiftlint:disable file_length
//
//  AnalyticsEventData.swift
//  RunAnywhere SDK
//
//  Structured event data models for strongly typed analytics
//

import Foundation

/// Base protocol for all structured event data
public protocol AnalyticsEventData: Codable, Sendable {}

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

// MARK: - STT Event Data Models

/// STT transcription completion data
public struct STTTranscriptionData: AnalyticsEventData {
    public let wordCount: Int
    public let confidence: Float
    public let durationMs: Double
    public let audioLengthMs: Double
    public let realTimeFactor: Double
    public let speakerId: String

    public init(wordCount: Int, confidence: Float, durationMs: Double, audioLengthMs: Double, realTimeFactor: Double, speakerId: String = "unknown") {
        self.wordCount = wordCount
        self.confidence = confidence
        self.durationMs = durationMs
        self.audioLengthMs = audioLengthMs
        self.realTimeFactor = realTimeFactor
        self.speakerId = speakerId
    }

}

/// Final transcript event data
public struct FinalTranscriptData: AnalyticsEventData {
    public let textLength: Int
    public let wordCount: Int
    public let confidence: Float
    public let speakerId: String
    public let timestamp: TimeInterval

    public init(textLength: Int, wordCount: Int, confidence: Float, speakerId: String = "unknown", timestamp: TimeInterval) {
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

// MARK: - Generation Event Data Models

/// Generation start event data
public struct GenerationStartData: AnalyticsEventData {
    public let generationId: String
    public let modelId: String
    public let executionTarget: String
    public let promptTokens: Int
    public let maxTokens: Int

    public init(generationId: String, modelId: String, executionTarget: String, promptTokens: Int, maxTokens: Int) {
        self.generationId = generationId
        self.modelId = modelId
        self.executionTarget = executionTarget
        self.promptTokens = promptTokens
        self.maxTokens = maxTokens
    }

}

/// Generation completion event data with full telemetry fields
public struct GenerationCompletionData: AnalyticsEventData {
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

    // LLM-specific fields
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let tokensPerSecond: Double?
    public let timeToFirstTokenMs: Double?
    public let promptEvalTimeMs: Double?
    public let generationTimeMs: Double?
    public let contextLength: Int?
    public let temperature: Double?
    public let maxTokens: Int?

    /// Legacy initializer for backward compatibility
    public init(generationId: String, modelId: String, executionTarget: String, inputTokens: Int, outputTokens: Int, totalTimeMs: Double, timeToFirstTokenMs: Double, tokensPerSecond: Double) {
        self.modelId = modelId
        self.modelName = nil
        self.framework = nil
        self.device = nil
        self.osVersion = nil
        self.platform = nil
        self.sdkVersion = nil
        self.processingTimeMs = totalTimeMs
        self.success = true
        self.errorMessage = nil
        self.errorCode = nil
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.promptEvalTimeMs = nil
        self.generationTimeMs = totalTimeMs
        self.contextLength = nil
        self.temperature = nil
        self.maxTokens = nil
    }

    /// Full initializer with all telemetry fields
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
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        tokensPerSecond: Double?,
        timeToFirstTokenMs: Double?,
        promptEvalTimeMs: Double? = nil,
        generationTimeMs: Double?,
        contextLength: Int? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
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
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.promptEvalTimeMs = promptEvalTimeMs
        self.generationTimeMs = generationTimeMs
        self.contextLength = contextLength
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Streaming update event data
public struct StreamingUpdateData: AnalyticsEventData {
    public let generationId: String
    public let tokensGenerated: Int

    public init(generationId: String, tokensGenerated: Int) {
        self.generationId = generationId
        self.tokensGenerated = tokensGenerated
    }

}

/// First token event data
public struct FirstTokenData: AnalyticsEventData {
    public let generationId: String
    public let timeToFirstTokenMs: Double

    public init(generationId: String, timeToFirstTokenMs: Double) {
        self.generationId = generationId
        self.timeToFirstTokenMs = timeToFirstTokenMs
    }
}

/// Model loading event data with full telemetry fields
public struct ModelLoadingData: AnalyticsEventData {
    // Model info
    public let modelId: String
    public let modelName: String?
    public let framework: String?

    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?
    public let errorCode: String?

    public init(
        modelId: String,
        loadTimeMs: Double,
        success: Bool,
        errorCode: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = nil
        self.framework = nil
        self.device = nil
        self.osVersion = nil
        self.platform = nil
        self.sdkVersion = nil
        self.processingTimeMs = loadTimeMs
        self.success = success
        self.errorMessage = nil
        self.errorCode = errorCode
    }

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
        errorCode: String? = nil
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
    }
}

/// Model unloading event data
public struct ModelUnloadingData: AnalyticsEventData {
    public let modelId: String
    public let timestamp: TimeInterval

    public init(modelId: String) {
        self.modelId = modelId
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - TTS Operation Event Data

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

// MARK: - STT Operation Event Data

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

// MARK: - Session Event Data Models

/// Session started event data
public struct SessionStartedData: AnalyticsEventData {
    public let modelId: String
    public let sessionType: String
    public let timestamp: TimeInterval

    public init(modelId: String, sessionType: String) {
        self.modelId = modelId
        self.sessionType = sessionType
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Session ended event data
public struct SessionEndedData: AnalyticsEventData {
    public let sessionId: String
    public let duration: TimeInterval
    public let timestamp: TimeInterval

    public init(sessionId: String, duration: TimeInterval) {
        self.sessionId = sessionId
        self.duration = duration
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Generic Error Data

/// Generic error event data with full context including stack trace
public struct ErrorEventData: AnalyticsEventData {
    /// The error description
    public let error: String

    /// The context where the error occurred (e.g., "generation", "stt", "tts")
    public let context: String

    /// Machine-readable error code
    public let errorCode: String?

    /// Error category for grouping
    public let category: String?

    /// Stack trace at the point of error (debug builds only)
    public let stackTrace: String?

    /// Source file where error occurred
    public let file: String?

    /// Line number where error occurred
    public let line: Int?

    /// Function name where error occurred
    public let function: String?

    /// Timestamp when the error occurred
    public let timestamp: TimeInterval

    /// Full initializer with all context fields
    public init(
        error: String,
        context: AnalyticsContext,
        errorCode: String? = nil,
        category: String? = nil,
        stackTrace: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        function: String? = nil
    ) {
        self.error = error
        self.context = context.rawValue
        self.errorCode = errorCode
        self.category = category
        self.stackTrace = stackTrace
        self.file = file
        self.line = line
        self.function = function
        self.timestamp = Date().timeIntervalSince1970
    }

    /// Convenience initializer from Error with automatic context capture
    public init(
        from error: Error,
        context: AnalyticsContext,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let raError = error.asRunAnywhereError()
        let errorContext = error.errorContext ?? ErrorContext(file: file, line: line, function: function)

        self.error = raError.errorDescription ?? error.localizedDescription
        self.context = context.rawValue
        self.errorCode = String(raError.code.rawValue)
        self.category = raError.category.rawValue
        self.file = errorContext.file
        self.line = errorContext.line
        self.function = errorContext.function
        self.timestamp = Date().timeIntervalSince1970

        // Only include stack trace in debug builds
        #if DEBUG
        self.stackTrace = errorContext.formattedStackTrace
        #else
        self.stackTrace = nil
        #endif
    }
}
