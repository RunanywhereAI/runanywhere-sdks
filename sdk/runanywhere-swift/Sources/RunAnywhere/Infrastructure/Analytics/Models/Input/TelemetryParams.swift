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

// MARK: - Telemetry Modality

/// Telemetry modality for V2 API routing.
///
/// The backend uses this to route events to normalized tables:
/// - `llm` → telemetry_events + llm_telemetry
/// - `stt` → telemetry_events + stt_telemetry
/// - `tts` → telemetry_events + tts_telemetry
/// - `model` → telemetry_events only (for download/extraction events)
///
/// If modality is nil, backend uses V1 table (backward compatible).
public enum TelemetryModality: String, Codable, Sendable, CaseIterable {
    case llm = "llm"
    case stt = "stt"
    case tts = "tts"
    case model = "model"

    /// Infer modality from event type prefix.
    ///
    /// This is the only inference needed - no framework mapping required.
    /// The event_type prefix is already strongly typed in the SDK.
    ///
    /// - Parameter eventType: The event type string (e.g., "stt_transcription_completed")
    /// - Returns: The inferred modality, or nil for SDK/device events (use V1)
    public static func infer(from eventType: String) -> TelemetryModality? {
        let eventLower = eventType.lowercased()

        // STT events - ALL STT events go to stt_telemetry (V2 path) for V1 deprecation
        // Fields are nullable - started/partial events will have nulls (expected)
        // This allows V1 deprecation while keeping all STT events in normalized table
        if eventLower.hasPrefix("stt_") {
            return .stt
        }

        // TTS events - ALL TTS events go to tts_telemetry (V2 path) for V1 deprecation
        // Fields are nullable - started/chunk events will have nulls (expected)
        // This allows V1 deprecation while keeping all TTS events in normalized table
        if eventLower.hasPrefix("tts_") {
            return .tts
        }

        // LLM events - all LLM events go to llm_telemetry (V2 path) for V1 deprecation
        // Token fields are nullable - started/first_token events will have nulls (expected)
        // This allows V1 deprecation while keeping all LLM events in normalized table
        if eventLower.hasPrefix("llm_") || eventLower.hasPrefix("generation_") {
            return .llm
        }

        // Model lifecycle events (download, extraction, deletion)
        if eventLower.hasPrefix("model_") {
            return .model
        }

        // SDK/device/error events → use V1 (nil modality)
        // e.g., sdk_initialized, device_registered, error_*
        return nil
    }

    /// Infer modality from a batch of events.
    ///
    /// **IMPORTANT**: Uses the first event's type to determine batch-level modality.
    /// This is a hint for the backend - the backend should use per-event modality
    /// for routing to specialized tables (stt_telemetry, llm_telemetry, etc.).
    ///
    /// If batches contain mixed event types, the backend must infer per-event modality
    /// from each event's `event_type` field, not from this batch-level hint.
    ///
    /// - Parameter events: Array of telemetry event payloads
    /// - Returns: The inferred modality from first event, or nil for V1 path
    public static func infer(from events: [TelemetryEventPayload]) -> TelemetryModality? {
        guard let firstEvent = events.first else {
            return nil
        }
        return infer(from: firstEvent.eventType)
    }
}
