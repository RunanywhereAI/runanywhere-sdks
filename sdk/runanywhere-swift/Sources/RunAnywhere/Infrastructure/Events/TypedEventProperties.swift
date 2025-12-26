//
//  TypedEventProperties.swift
//  RunAnywhere SDK
//
//  Strongly typed event properties protocol.
//  Events can provide typed data directly, avoiding string parsing.
//

import Foundation

// MARK: - Typed Event Properties Protocol

/// Protocol for events that provide strongly typed properties.
/// Events implementing this can skip string conversion/parsing entirely.
public protocol TypedEventProperties: SDKEvent {
    /// Typed properties that map directly to TelemetryEventPayload fields.
    /// These values are used directly without string parsing.
    var typedProperties: EventProperties { get }
}

// MARK: - Event Properties Container

/// Strongly typed container for event properties.
/// All fields are optional - only set what's relevant for the event.
public struct EventProperties: Sendable {
    // MARK: - Model Info

    public var modelId: String?
    public var modelName: String?
    public var framework: String?

    // MARK: - Common Metrics

    public var processingTimeMs: Double?
    public var success: Bool?
    public var errorMessage: String?
    public var errorCode: String?

    // MARK: - LLM Fields

    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var tokensPerSecond: Double?
    public var timeToFirstTokenMs: Double?
    public var promptEvalTimeMs: Double?
    public var generationTimeMs: Double?
    public var contextLength: Int?
    public var temperature: Double?
    public var maxTokens: Int?
    public var isStreaming: Bool?
    public var generationId: String?

    // MARK: - STT Fields

    public var audioDurationMs: Double?
    public var realTimeFactor: Double?
    public var wordCount: Int?
    public var confidence: Double?
    public var language: String?
    public var segmentIndex: Int?
    public var transcriptionId: String?

    // MARK: - TTS Fields

    public var characterCount: Int?
    public var charactersPerSecond: Double?
    public var audioSizeBytes: Int?
    public var sampleRate: Int?
    public var voice: String?
    public var outputDurationMs: Double?
    public var synthesisId: String?

    // MARK: - Model Lifecycle

    public var modelSizeBytes: Int64?
    public var durationMs: Double?
    public var bytesDownloaded: Int64?
    public var totalBytes: Int64?
    public var progress: Double?
    public var archiveType: String?

    // MARK: - Initialization

    public init(
        modelId: String? = nil,
        modelName: String? = nil,
        framework: String? = nil,
        processingTimeMs: Double? = nil,
        success: Bool? = nil,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        tokensPerSecond: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        promptEvalTimeMs: Double? = nil,
        generationTimeMs: Double? = nil,
        contextLength: Int? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        isStreaming: Bool? = nil,
        generationId: String? = nil,
        audioDurationMs: Double? = nil,
        realTimeFactor: Double? = nil,
        wordCount: Int? = nil,
        confidence: Double? = nil,
        language: String? = nil,
        segmentIndex: Int? = nil,
        transcriptionId: String? = nil,
        characterCount: Int? = nil,
        charactersPerSecond: Double? = nil,
        audioSizeBytes: Int? = nil,
        sampleRate: Int? = nil,
        voice: String? = nil,
        outputDurationMs: Double? = nil,
        synthesisId: String? = nil,
        modelSizeBytes: Int64? = nil,
        durationMs: Double? = nil,
        bytesDownloaded: Int64? = nil,
        totalBytes: Int64? = nil,
        progress: Double? = nil,
        archiveType: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
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
        self.isStreaming = isStreaming
        self.generationId = generationId
        self.audioDurationMs = audioDurationMs
        self.realTimeFactor = realTimeFactor
        self.wordCount = wordCount
        self.confidence = confidence
        self.language = language
        self.segmentIndex = segmentIndex
        self.transcriptionId = transcriptionId
        self.characterCount = characterCount
        self.charactersPerSecond = charactersPerSecond
        self.audioSizeBytes = audioSizeBytes
        self.sampleRate = sampleRate
        self.voice = voice
        self.outputDurationMs = outputDurationMs
        self.synthesisId = synthesisId
        self.modelSizeBytes = modelSizeBytes
        self.durationMs = durationMs
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.progress = progress
        self.archiveType = archiveType
    }
}

// MARK: - Validation

extension EventProperties {
    /// Validate event properties for data quality guardrails.
    /// - Throws: ValidationError if any values are invalid
    public func validate() throws {
        // Token counts must be non-negative
        if let tokens = inputTokens, tokens < 0 {
            throw EventValidationError.invalidValue(field: "inputTokens", reason: "must be >= 0")
        }
        if let tokens = outputTokens, tokens < 0 {
            throw EventValidationError.invalidValue(field: "outputTokens", reason: "must be >= 0")
        }

        // Performance metrics must be positive
        if let tps = tokensPerSecond, tps < 0 {
            throw EventValidationError.invalidValue(field: "tokensPerSecond", reason: "must be >= 0")
        }
        if let time = processingTimeMs, time < 0 {
            throw EventValidationError.invalidValue(field: "processingTimeMs", reason: "must be >= 0")
        }
        if let ttft = timeToFirstTokenMs, ttft < 0 {
            throw EventValidationError.invalidValue(field: "timeToFirstTokenMs", reason: "must be >= 0")
        }

        // Confidence must be 0-1
        if let conf = confidence, conf < 0 || conf > 1 {
            throw EventValidationError.invalidValue(field: "confidence", reason: "must be between 0 and 1")
        }

        // Progress must be 0-100
        if let prog = progress, prog < 0 || prog > 100 {
            throw EventValidationError.invalidValue(field: "progress", reason: "must be between 0 and 100")
        }

        // Total tokens should equal input + output if all are present
        if let input = inputTokens, let output = outputTokens, let total = totalTokens {
            if total != input + output {
                throw EventValidationError.invalidValue(
                    field: "totalTokens",
                    reason: "must equal inputTokens + outputTokens (\(input) + \(output) = \(input + output), got \(total))"
                )
            }
        }
    }
}

// MARK: - Validation Error

/// Error thrown when event properties fail validation
public enum EventValidationError: LocalizedError {
    case invalidValue(field: String, reason: String)
    case missingRequiredField(field: String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let field, let reason):
            return "Invalid value for '\(field)': \(reason)"
        case .missingRequiredField(let field):
            return "Missing required field: '\(field)'"
        }
    }
}
