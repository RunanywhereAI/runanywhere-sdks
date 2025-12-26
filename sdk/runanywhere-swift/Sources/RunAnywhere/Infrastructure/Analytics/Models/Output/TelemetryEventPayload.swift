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

    // MARK: - Event Classification

    /// Event modality for V2 routing (llm, stt, tts, model, system)
    public let modality: String?

    // MARK: - Device Identification

    /// Persistent device UUID (for V2 base table)
    public let deviceId: String?

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
    // NOTE: Production (FastAPI) uses `id` and `timestamp`
    //       Development (Supabase) uses `sdk_event_id` and `event_timestamp`
    //       The encode(to:) method handles this difference based on productionEncodingMode

    enum CodingKeys: String, CodingKey {
        case id  // Production: "id", Development: manually encoded as "sdk_event_id"
        case eventType = "event_type"
        case timestamp  // Production: "timestamp", Development: manually encoded as "event_timestamp"
        case createdAt = "created_at"
        case modality  // Only used for Supabase; skipped in production encoding
        case deviceId = "device_id"  // Only used for Supabase; skipped in production encoding
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

    /// Dynamic coding key for environment-specific field names
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    // MARK: - Environment-Aware Encoding

    /// Flag to control encoding mode (set by RemoteTelemetryDataSource based on environment)
    /// - `true`: Production mode - skip `modality` and `device_id` (FastAPI has them at batch level)
    /// - `false`: Development mode - include all fields (Supabase needs them per event)
    public static var productionEncodingMode = false

    /// Custom encoder that handles both Supabase (all keys) and FastAPI (skip batch-level fields).
    /// - Production (FastAPI): uses `id` and `timestamp`
    /// - Development (Supabase): uses `sdk_event_id` and `event_timestamp`
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Required fields - use different key names based on environment
        if Self.productionEncodingMode {
            // Production: FastAPI expects "id" and "timestamp"
            try container.encode(id, forKey: .id)
            try container.encode(timestamp, forKey: .timestamp)
        } else {
            // Development: Supabase expects "sdk_event_id" and "event_timestamp"
            var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            try dynamicContainer.encode(id, forKey: DynamicCodingKey(stringValue: "sdk_event_id"))
            try dynamicContainer.encode(timestamp, forKey: DynamicCodingKey(stringValue: "event_timestamp"))
        }
        try container.encode(eventType, forKey: .eventType)
        try container.encode(createdAt, forKey: .createdAt)

        // Conditional fields - skip for production (FastAPI has them at batch level)
        if !Self.productionEncodingMode {
            try container.encode(modality, forKey: .modality)
            try container.encode(deviceId, forKey: .deviceId)
        }

        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(framework, forKey: .framework)
        try container.encode(device, forKey: .device)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(platform, forKey: .platform)
        try container.encode(sdkVersion, forKey: .sdkVersion)
        try container.encode(processingTimeMs, forKey: .processingTimeMs)
        try container.encode(success, forKey: .success)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(tokensPerSecond, forKey: .tokensPerSecond)
        try container.encode(timeToFirstTokenMs, forKey: .timeToFirstTokenMs)
        try container.encode(promptEvalTimeMs, forKey: .promptEvalTimeMs)
        try container.encode(generationTimeMs, forKey: .generationTimeMs)
        try container.encode(contextLength, forKey: .contextLength)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(audioDurationMs, forKey: .audioDurationMs)
        try container.encode(realTimeFactor, forKey: .realTimeFactor)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(language, forKey: .language)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(segmentIndex, forKey: .segmentIndex)
        try container.encode(characterCount, forKey: .characterCount)
        try container.encode(charactersPerSecond, forKey: .charactersPerSecond)
        try container.encode(audioSizeBytes, forKey: .audioSizeBytes)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(voice, forKey: .voice)
        try container.encode(outputDurationMs, forKey: .outputDurationMs)
    }

    // MARK: - Initializer

    public init(
        id: String,
        eventType: String,
        timestamp: Date,
        createdAt: Date,
        modality: String? = nil,
        deviceId: String? = nil,
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
        self.modality = modality
        self.deviceId = deviceId
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

// MARK: - Conversion from SDKEvent

extension TelemetryEventPayload {
    /// Create payload directly from SDKEvent (preserves category → modality).
    /// Use this for events that don't have typed properties.
    public init(from event: any SDKEvent) {
        self.id = event.id
        self.eventType = event.type
        self.timestamp = event.timestamp
        self.createdAt = Date()

        // V2 required fields - use event category directly (single source of truth!)
        self.modality = Self.modalityFromCategory(event.category)
        self.deviceId = DeviceIdentity.persistentUUID
        self.sessionId = event.sessionId

        // Parse properties from event's string dictionary
        let props = event.properties
        self.modelId = props["model_id"] ?? props["voice_id"]
        self.modelName = props["model_name"]
        self.framework = props["framework"]

        // Device info
        let deviceInfo = DeviceInfo.current
        self.device = deviceInfo.deviceModel
        self.osVersion = deviceInfo.osVersion
        self.platform = deviceInfo.platform
        self.sdkVersion = SDKConstants.version

        // Common metrics
        self.processingTimeMs = Self.parseDouble(
            props["processing_time_ms"] ?? props["processing_duration_ms"] ?? props["duration_ms"]
        )
        self.success = Self.parseBool(props["success"])
        self.errorMessage = props["error_message"] ?? props["error"]
        self.errorCode = props["error_code"]

        // LLM fields
        self.inputTokens = Self.parseInt(props["input_tokens"])
        self.outputTokens = Self.parseInt(props["output_tokens"])
        self.totalTokens = Self.parseInt(props["total_tokens"])
        self.tokensPerSecond = Self.parseDouble(props["tokens_per_second"])
        self.timeToFirstTokenMs = Self.parseDouble(props["time_to_first_token_ms"])
        self.promptEvalTimeMs = Self.parseDouble(props["prompt_eval_time_ms"])
        self.generationTimeMs = Self.parseDouble(props["generation_time_ms"])
        self.contextLength = Self.parseInt(props["context_length"])
        self.temperature = Self.parseDouble(props["temperature"])
        self.maxTokens = Self.parseInt(props["max_tokens"])

        // STT fields
        self.audioDurationMs = Self.parseDouble(props["audio_duration_ms"] ?? props["audio_length_ms"])
        self.realTimeFactor = Self.parseDouble(props["real_time_factor"])
        self.wordCount = Self.parseInt(props["word_count"])
        self.confidence = Self.parseDouble(props["confidence"])
        self.language = props["language"]
        self.isStreaming = Self.parseBool(props["is_streaming"])
        self.segmentIndex = Self.parseInt(props["segment_index"])

        // TTS fields
        self.characterCount = Self.parseInt(props["character_count"] ?? props["text_length"])
        self.charactersPerSecond = Self.parseDouble(props["characters_per_second"])
        self.audioSizeBytes = Self.parseInt(props["audio_size_bytes"])
        self.sampleRate = Self.parseInt(props["sample_rate"])
        self.voice = props["voice"] ?? props["voice_id"]
        self.outputDurationMs = Self.parseDouble(props["output_duration_ms"] ?? props["audio_duration_ms"])
    }

    /// Create payload from strongly typed event properties.
    /// This avoids string parsing entirely - types are preserved directly.
    public init(
        from event: any SDKEvent,
        typedProperties props: EventProperties
    ) {
        self.id = event.id
        self.eventType = event.type
        self.timestamp = event.timestamp
        self.createdAt = Date()

        // V2 required fields - use event category directly
        self.modality = Self.modalityFromCategory(event.category)
        self.deviceId = DeviceIdentity.persistentUUID
        self.sessionId = event.sessionId

        // Model info - directly from typed properties
        self.modelId = props.modelId
        self.modelName = props.modelName
        self.framework = props.framework

        // Device info
        let deviceInfo = DeviceInfo.current
        self.device = deviceInfo.deviceModel
        self.osVersion = deviceInfo.osVersion
        self.platform = deviceInfo.platform
        self.sdkVersion = SDKConstants.version

        // Common metrics - typed values, no parsing needed!
        self.processingTimeMs = props.processingTimeMs ?? props.durationMs
        self.success = props.success
        self.errorMessage = props.errorMessage
        self.errorCode = props.errorCode

        // LLM fields - typed values, no parsing needed!
        self.inputTokens = props.inputTokens
        self.outputTokens = props.outputTokens
        self.totalTokens = props.totalTokens ?? {
            if let input = props.inputTokens, let output = props.outputTokens {
                return input + output
            }
            return nil
        }()
        self.tokensPerSecond = props.tokensPerSecond
        self.timeToFirstTokenMs = props.timeToFirstTokenMs
        self.promptEvalTimeMs = props.promptEvalTimeMs
        self.generationTimeMs = props.generationTimeMs
        self.contextLength = props.contextLength
        self.temperature = props.temperature
        self.maxTokens = props.maxTokens

        // STT fields - typed values!
        self.audioDurationMs = props.audioDurationMs
        self.realTimeFactor = props.realTimeFactor
        self.wordCount = props.wordCount
        self.confidence = props.confidence
        self.language = props.language
        self.isStreaming = props.isStreaming
        self.segmentIndex = props.segmentIndex

        // TTS fields - typed values!
        self.characterCount = props.characterCount
        self.charactersPerSecond = props.charactersPerSecond
        self.audioSizeBytes = props.audioSizeBytes
        self.sampleRate = props.sampleRate
        self.voice = props.voice
        self.outputDurationMs = props.outputDurationMs
    }

    // MARK: - Modality Mapping (Single Source of Truth)

    /// Convert EventCategory to modality string for V2 routing.
    /// This is the ONLY place that defines category → modality mapping.
    private static func modalityFromCategory(_ category: EventCategory) -> String {
        switch category {
        case .llm, .stt, .tts, .model:
            return category.rawValue
        default:
            return "system"
        }
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

/// Batch telemetry request for API.
///
/// Supports both V1 and V2 storage paths:
/// - V1 (legacy): Set `modality` to nil → stores in `sdk_telemetry_events` table
/// - V2 (normalized): Set `modality` to "llm"/"stt"/"tts"/"model" → stores in normalized tables
public struct TelemetryBatchRequest: Codable, Sendable {
    public let events: [TelemetryEventPayload]
    public let deviceId: String
    public let timestamp: Date

    /// Optional modality for V2 API routing.
    ///
    /// - `nil` → V1 path (backward compatible, uses legacy `sdk_telemetry_events` table)
    /// - `"llm"` → V2 path (uses `telemetry_events` + `llm_telemetry` tables)
    /// - `"stt"` → V2 path (uses `telemetry_events` + `stt_telemetry` tables)
    /// - `"tts"` → V2 path (uses `telemetry_events` + `tts_telemetry` tables)
    /// - `"model"` → V2 path (uses `telemetry_events` table only, for download/extraction)
    public let modality: String?

    enum CodingKeys: String, CodingKey {
        case events
        case deviceId = "device_id"
        case timestamp
        case modality
    }

    /// V1 initializer (backward compatible - no modality, uses legacy table)
    public init(events: [TelemetryEventPayload], deviceId: String, timestamp: Date = Date()) {
        self.events = events
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.modality = nil
    }

    /// V2 initializer with modality string for normalized table routing.
    ///
    /// Use this when the modality is already known as a string (e.g., from grouped payloads).
    ///
    /// - Parameters:
    ///   - events: Array of telemetry events to send
    ///   - deviceId: Persistent device UUID
    ///   - timestamp: When the batch was created
    ///   - modality: The modality string for V2 routing (llm/stt/tts/model), or nil for V1 legacy
    public init(
        events: [TelemetryEventPayload],
        deviceId: String,
        timestamp: Date = Date(),
        modality: String?
    ) {
        self.events = events
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.modality = modality
    }
}

/// Batch telemetry response from API
public struct TelemetryBatchResponse: Codable, Sendable {
    public let success: Bool
    public let eventsReceived: Int
    public let eventsStored: Int

    /// Number of duplicate events skipped (idempotency)
    public let eventsSkipped: Int?

    /// Array of error messages if any events failed
    public let errors: [String]?

    /// Storage path used: "V1" (legacy) or "V2" (normalized)
    public let storageVersion: String?

    enum CodingKeys: String, CodingKey {
        case success
        case eventsReceived = "events_received"
        case eventsStored = "events_stored"
        case eventsSkipped = "events_skipped"
        case errors
        case storageVersion = "storage_version"
    }
}
