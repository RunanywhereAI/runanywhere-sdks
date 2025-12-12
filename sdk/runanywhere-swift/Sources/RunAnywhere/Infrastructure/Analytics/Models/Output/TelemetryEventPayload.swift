//
//  TelemetryEventPayload.swift
//  RunAnywhere SDK
//
//  Typed telemetry payload for backend API transmission.
//  NO JSON properties dictionary - all fields are strongly typed.
//

import Foundation

/// Typed telemetry event payload for API transmission.
/// Maps to backend SDKTelemetryEvent schema with strongly typed fields.
public struct TelemetryEventPayload: Codable, Sendable {
    // MARK: - Required Fields

    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let createdAt: Date

    // MARK: - Session Tracking

    public let sessionId: String?

    // MARK: - Model Info

    public let modelId: String?
    public let modelName: String?
    public let framework: String?

    // MARK: - Device Info

    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // MARK: - Common Performance Metrics

    public let processingTimeMs: Double?
    public let success: Bool?
    public let errorMessage: String?
    public let errorCode: String?

    // MARK: - LLM-specific Fields

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

    // MARK: - STT-specific Fields

    public let audioDurationMs: Double?
    public let realTimeFactor: Double?
    public let wordCount: Int?
    public let confidence: Double?
    public let language: String?
    public let isStreaming: Bool?
    public let segmentIndex: Int?

    // MARK: - TTS-specific Fields

    public let characterCount: Int?
    public let charactersPerSecond: Double?
    public let audioSizeBytes: Int?
    public let sampleRate: Int?
    public let voice: String?
    public let outputDurationMs: Double?

    // MARK: - Coding Keys (snake_case for API)

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case timestamp
        case createdAt = "created_at"
        case sessionId = "session_id"
        case modelId = "model_id"
        case modelName = "model_name"
        case framework
        case device
        case osVersion = "os_version"
        case platform
        case sdkVersion = "sdk_version"
        case processingTimeMs = "processing_time_ms"
        case success
        case errorMessage = "error_message"
        case errorCode = "error_code"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case tokensPerSecond = "tokens_per_second"
        case timeToFirstTokenMs = "time_to_first_token_ms"
        case promptEvalTimeMs = "prompt_eval_time_ms"
        case generationTimeMs = "generation_time_ms"
        case contextLength = "context_length"
        case temperature
        case maxTokens = "max_tokens"
        case audioDurationMs = "audio_duration_ms"
        case realTimeFactor = "real_time_factor"
        case wordCount = "word_count"
        case confidence
        case language
        case isStreaming = "is_streaming"
        case segmentIndex = "segment_index"
        case characterCount = "character_count"
        case charactersPerSecond = "characters_per_second"
        case audioSizeBytes = "audio_size_bytes"
        case sampleRate = "sample_rate"
        case voice
        case outputDurationMs = "output_duration_ms"
    }

    // MARK: - Initializer

    public init(
        id: String,
        eventType: String,
        timestamp: Date,
        createdAt: Date,
        sessionId: String? = nil,
        modelId: String? = nil,
        modelName: String? = nil,
        framework: String? = nil,
        device: String? = nil,
        osVersion: String? = nil,
        platform: String? = nil,
        sdkVersion: String? = nil,
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
        audioDurationMs: Double? = nil,
        realTimeFactor: Double? = nil,
        wordCount: Int? = nil,
        confidence: Double? = nil,
        language: String? = nil,
        isStreaming: Bool? = nil,
        segmentIndex: Int? = nil,
        characterCount: Int? = nil,
        charactersPerSecond: Double? = nil,
        audioSizeBytes: Int? = nil,
        sampleRate: Int? = nil,
        voice: String? = nil,
        outputDurationMs: Double? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.sessionId = sessionId
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
        self.audioDurationMs = audioDurationMs
        self.realTimeFactor = realTimeFactor
        self.wordCount = wordCount
        self.confidence = confidence
        self.language = language
        self.isStreaming = isStreaming
        self.segmentIndex = segmentIndex
        self.characterCount = characterCount
        self.charactersPerSecond = charactersPerSecond
        self.audioSizeBytes = audioSizeBytes
        self.sampleRate = sampleRate
        self.voice = voice
        self.outputDurationMs = outputDurationMs
    }
}

// MARK: - Conversion from TelemetryData

extension TelemetryEventPayload {
    /// Convert from local TelemetryData (with properties dict) to typed payload for API
    public init(from telemetryData: TelemetryData) {
        self.id = telemetryData.id
        self.eventType = telemetryData.eventType
        self.timestamp = telemetryData.timestamp
        self.createdAt = telemetryData.createdAt

        let props = telemetryData.properties

        // Session
        self.sessionId = props["session_id"]

        // Model info
        self.modelId = props["model_id"]
        self.modelName = props["model_name"]
        self.framework = props["framework"]

        // Device info
        self.device = props["device"]
        self.osVersion = props["os_version"]
        self.platform = props["platform"]
        self.sdkVersion = props["sdk_version"]

        // Common metrics
        self.processingTimeMs = Self.parseDouble(props["processing_time_ms"] ?? props["total_time_ms"])
        self.success = Self.parseBool(props["success"])
        self.errorMessage = props["error_message"]
        self.errorCode = props["error_code"]

        // LLM
        self.inputTokens = Self.parseInt(props["input_tokens"] ?? props["prompt_tokens"])
        self.outputTokens = Self.parseInt(props["output_tokens"])
        self.totalTokens = Self.parseInt(props["total_tokens"])
        self.tokensPerSecond = Self.parseDouble(props["tokens_per_second"])
        self.timeToFirstTokenMs = Self.parseDouble(props["time_to_first_token_ms"])
        self.promptEvalTimeMs = Self.parseDouble(props["prompt_eval_time_ms"])
        self.generationTimeMs = Self.parseDouble(props["generation_time_ms"])
        self.contextLength = Self.parseInt(props["context_length"])
        self.temperature = Self.parseDouble(props["temperature"])
        self.maxTokens = Self.parseInt(props["max_tokens"])

        // STT
        self.audioDurationMs = Self.parseDouble(props["audio_duration_ms"])
        self.realTimeFactor = Self.parseDouble(props["real_time_factor"])
        self.wordCount = Self.parseInt(props["word_count"])
        self.confidence = Self.parseDouble(props["confidence"])
        self.language = props["language"]
        self.isStreaming = Self.parseBool(props["is_streaming"])
        self.segmentIndex = Self.parseInt(props["segment_index"])

        // TTS
        self.characterCount = Self.parseInt(props["character_count"])
        self.charactersPerSecond = Self.parseDouble(props["characters_per_second"])
        self.audioSizeBytes = Self.parseInt(props["audio_size_bytes"])
        self.sampleRate = Self.parseInt(props["sample_rate"])
        self.voice = props["voice"]
        self.outputDurationMs = Self.parseDouble(props["output_duration_ms"] ?? props["audio_duration_ms"])
    }

    // MARK: - Private Helpers

    private static func parseDouble(_ value: String?) -> Double? {
        guard let value = value else { return nil }
        return Double(value)
    }

    private static func parseInt(_ value: String?) -> Int? {
        guard let value = value else { return nil }
        return Int(value)
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value = value else { return nil }
        return value.lowercased() == "true" || value == "1"
    }
}

// MARK: - Batch Request/Response

/// Batch telemetry request for API
public struct TelemetryBatchRequest: Codable, Sendable {
    public let events: [TelemetryEventPayload]
    public let deviceId: String
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case events
        case deviceId = "device_id"
        case timestamp
    }

    public init(events: [TelemetryEventPayload], deviceId: String, timestamp: Date = Date()) {
        self.events = events
        self.deviceId = deviceId
        self.timestamp = timestamp
    }
}

/// Batch telemetry response from API
public struct TelemetryBatchResponse: Codable, Sendable {
    public let success: Bool
    public let eventsReceived: Int
    public let eventsStored: Int
    public let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case success
        case eventsReceived = "events_received"
        case eventsStored = "events_stored"
        case errors
    }
}
