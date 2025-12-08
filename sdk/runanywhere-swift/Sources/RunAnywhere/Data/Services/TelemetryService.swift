// swiftlint:disable file_length
//
//  TelemetryService.swift
//  RunAnywhere SDK
//
//  Service layer for telemetry and analytics management
//

import Foundation

// MARK: - Telemetry Parameter Structs

/// Parameters for tracking generation start events
public struct GenerationStartParams {
    let generationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let promptTokens: Int
    let maxTokens: Int
    let device: String
    let osVersion: String
}

/// Parameters for tracking generation completion events
public struct GenerationCompletedParams {
    let generationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTimeMs: Double
    let timeToFirstTokenMs: Double
    let tokensPerSecond: Double
    let device: String
    let osVersion: String
}

/// Parameters for tracking generation failure events
public struct GenerationFailedParams {
    let generationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let inputTokens: Int
    let totalTimeMs: Double
    let errorMessage: String
    let device: String
    let osVersion: String
}

/// Parameters for tracking STT model load events
public struct STTModelLoadParams {
    let modelId: String
    let modelName: String
    let framework: String
    let loadTimeMs: Double
    let modelSizeBytes: Int64?
    let device: String
    let osVersion: String
    let success: Bool
    let errorMessage: String?
}

/// Parameters for tracking STT transcription events
public struct STTTranscriptionParams {
    let transcriptionId: String
    let modelId: String
    let modelName: String
    let framework: String
    let audioDurationMs: Double
    let transcriptionTimeMs: Double
    let realTimeFactor: Double
    let wordCount: Int
    let confidence: Double?
    let device: String
    let osVersion: String
    let success: Bool
    let errorMessage: String?
}

/// Parameters for tracking TTS synthesis events
public struct TTSSynthesisParams {
    let synthesisId: String
    let modelId: String
    let modelName: String
    let framework: String
    let textLength: Int
    let audioDurationMs: Double
    let synthesisTimeMs: Double
    let realTimeFactor: Double
    let device: String
    let osVersion: String
    let success: Bool
    let errorMessage: String?
}

/// Service for managing telemetry data and analytics
public actor TelemetryService { // swiftlint:disable:this type_body_length
    private let logger = SDKLogger(category: "TelemetryService")
    private let telemetryRepository: any TelemetryRepository
    private let syncCoordinator: SyncCoordinator?

    // MARK: - Initialization

    public init(telemetryRepository: any TelemetryRepository, syncCoordinator: SyncCoordinator?) {
        self.telemetryRepository = telemetryRepository
        self.syncCoordinator = syncCoordinator
        logger.info("TelemetryService initialized")
    }

    // MARK: - Public Methods

    /// Track a telemetry event
    public func trackEvent(
        _ type: TelemetryEventType,
        properties: [String: String] = [:]
    ) async throws {
        try await telemetryRepository.trackEvent(type, properties: properties)
        logger.debug("Event tracked: \(type.rawValue)")
    }

    /// Track a custom event
    public func trackCustomEvent(
        _ name: String,
        properties: [String: String] = [:]
    ) async throws {
        let eventType = TelemetryEventType(rawValue: name) ?? .custom
        try await trackEvent(eventType, properties: properties)
    }

    /// Get all telemetry events
    public func getAllEvents() async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchAll()
    }

    /// Get events within date range
    public func getEvents(from startDate: Date, to endDate: Date) async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchByDateRange(from: startDate, to: endDate)
    }

    /// Get unsent events
    public func getUnsentEvents() async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchUnsent()
    }

    /// Mark events as sent
    public func markEventsSent(_ eventIds: [String]) async throws {
        try await telemetryRepository.markAsSent(eventIds)
        logger.info("Marked \(eventIds.count) events as sent")
    }

    /// Clean up old events
    public func cleanupOldEvents(olderThan date: Date) async throws {
        try await telemetryRepository.cleanup(olderThan: date)
        logger.info("Cleaned up events older than \(date)")
    }

    /// Force sync telemetry data
    public func syncTelemetry() async throws {
        if let syncCoordinator = syncCoordinator,
           let repository = telemetryRepository as? TelemetryRepositoryImpl {
            try await syncCoordinator.sync(repository)
            logger.info("Telemetry sync triggered")
        }
    }

    // MARK: - SDK Initialization

    /// Track SDK initialization
    public func trackInitialization(apiKey: String, version: String) async throws {
        try await trackEvent(.custom, properties: [
            "event": "initialized",
            "api_key_prefix": String(apiKey.prefix(8)),
            "sdk_version": version
        ])
    }

    // MARK: - Model Loading

    /// Track model loading (generic)
    public func trackModelLoad(  // swiftlint:disable:this function_parameter_count
        modelId: String,
        modelName: String,
        framework: String,
        modality: String,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) async throws {
        var properties: [String: String] = [
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "modality": modality,
            "load_time_ms": String(format: "%.1f", loadTimeMs),
            "device": device,
            "os_version": osVersion,
            "success": String(success)
        ]

        if let size = modelSizeBytes {
            properties["model_size_bytes"] = String(size)
        }
        if let error = errorMessage {
            properties["error_message"] = error
        }

        let eventType: TelemetryEventType = success ? .modelLoaded : .modelLoadFailed
        try await trackEvent(eventType, properties: properties)
    }

    // MARK: - LLM Generation (Text-to-Text)

    /// Track LLM generation start
    public func trackGenerationStarted(  // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        promptTokens: Int,
        maxTokens: Int,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.generationStarted, properties: [
            "generation_id": generationId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "prompt_tokens": String(promptTokens),
            "max_tokens": String(maxTokens),
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track LLM generation completion with full metrics
    public func trackGenerationCompleted(  // swiftlint:disable:this function_parameter_count
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
    ) async throws {
        try await trackEvent(.generationCompleted, properties: [
            "generation_id": generationId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "input_tokens": String(inputTokens),
            "output_tokens": String(outputTokens),
            "total_tokens": String(inputTokens + outputTokens),
            "total_time_ms": String(format: "%.1f", totalTimeMs),
            "time_to_first_token_ms": String(format: "%.1f", timeToFirstTokenMs),
            "tokens_per_second": String(format: "%.2f", tokensPerSecond),
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track LLM generation failure
    public func trackGenerationFailed(  // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        inputTokens: Int,
        totalTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.generationFailed, properties: [
            "generation_id": generationId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "input_tokens": String(inputTokens),
            "total_time_ms": String(format: "%.1f", totalTimeMs),
            "error_message": errorMessage,
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Legacy track generation (kept for backward compatibility)
    public func trackGeneration(
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        duration: TimeInterval
    ) async throws {
        try await trackEvent(.generationCompleted, properties: [
            "model_id": modelId,
            "input_tokens": String(inputTokens),
            "output_tokens": String(outputTokens),
            "duration_ms": String(Int(duration * 1000)),
            "tokens_per_second": String(Double(outputTokens) / duration)
        ])
    }

    // MARK: - STT (Speech-to-Text)

    /// Track STT model load
    public func trackSTTModelLoad(  // swiftlint:disable:this function_parameter_count
        modelId: String,
        modelName: String,
        framework: String,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) async throws {
        var properties: [String: String] = [
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "load_time_ms": String(format: "%.1f", loadTimeMs),
            "device": device,
            "os_version": osVersion,
            "success": String(success)
        ]

        if let size = modelSizeBytes {
            properties["model_size_bytes"] = String(size)
        }
        if let error = errorMessage {
            properties["error_message"] = error
        }

        let eventType: TelemetryEventType = success ? .sttModelLoaded : .sttModelLoadFailed
        try await trackEvent(eventType, properties: properties)
    }

    /// Track STT transcription start
    public func trackSTTTranscriptionStarted(  // swiftlint:disable:this function_parameter_count
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.sttTranscriptionStarted, properties: [
            "session_id": sessionId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track STT transcription completion with full metrics
    public func trackSTTTranscriptionCompleted(  // swiftlint:disable:this function_parameter_count
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        realTimeFactor: Double,
        wordCount: Int,
        characterCount: Int,
        confidence: Float,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.sttTranscriptionCompleted, properties: [
            "session_id": sessionId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "audio_duration_ms": String(format: "%.1f", audioDurationMs),
            "processing_time_ms": String(format: "%.1f", processingTimeMs),
            "real_time_factor": String(format: "%.3f", realTimeFactor),
            "word_count": String(wordCount),
            "character_count": String(characterCount),
            "confidence": String(format: "%.3f", confidence),
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track STT transcription failure
    public func trackSTTTranscriptionFailed(  // swiftlint:disable:this function_parameter_count
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.sttTranscriptionFailed, properties: [
            "session_id": sessionId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "audio_duration_ms": String(format: "%.1f", audioDurationMs),
            "processing_time_ms": String(format: "%.1f", processingTimeMs),
            "error_message": errorMessage,
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track STT streaming update (for real-time transcription)
    public func trackSTTStreamingUpdate(
        sessionId: String,
        modelId: String,
        framework: String,
        partialWordCount: Int,
        elapsedMs: Double
    ) async throws {
        try await trackEvent(.sttStreamingUpdate, properties: [
            "session_id": sessionId,
            "model_id": modelId,
            "framework": framework,
            "partial_word_count": String(partialWordCount),
            "elapsed_ms": String(format: "%.1f", elapsedMs)
        ])
    }

    // MARK: - TTS (Text-to-Speech)

    /// Track TTS model load
    public func trackTTSModelLoad(  // swiftlint:disable:this function_parameter_count
        modelId: String,
        modelName: String,
        framework: String,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        device: String,
        osVersion: String,
        success: Bool,
        errorMessage: String? = nil
    ) async throws {
        var properties: [String: String] = [
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "load_time_ms": String(format: "%.1f", loadTimeMs),
            "device": device,
            "os_version": osVersion,
            "success": String(success)
        ]

        if let size = modelSizeBytes {
            properties["model_size_bytes"] = String(size)
        }
        if let error = errorMessage {
            properties["error_message"] = error
        }

        let eventType: TelemetryEventType = success ? .ttsModelLoaded : .ttsModelLoadFailed
        try await trackEvent(eventType, properties: properties)
    }

    /// Track TTS synthesis start
    public func trackTTSSynthesisStarted(  // swiftlint:disable:this function_parameter_count
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        voice: String,
        characterCount: Int,
        speakingRate: Float,
        pitch: Float,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.ttsSynthesisStarted, properties: [
            "synthesis_id": synthesisId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "voice": voice,
            "character_count": String(characterCount),
            "speaking_rate": String(format: "%.2f", speakingRate),
            "pitch": String(format: "%.2f", pitch),
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track TTS synthesis completion with full metrics
    public func trackTTSSynthesisCompleted(  // swiftlint:disable:this function_parameter_count
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        sampleRate: Int,
        processingTimeMs: Double,
        charactersPerSecond: Double,
        realTimeFactor: Double,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.ttsSynthesisCompleted, properties: [
            "synthesis_id": synthesisId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "character_count": String(characterCount),
            "audio_duration_ms": String(format: "%.1f", audioDurationMs),
            "audio_size_bytes": String(audioSizeBytes),
            "sample_rate": String(sampleRate),
            "processing_time_ms": String(format: "%.1f", processingTimeMs),
            "characters_per_second": String(format: "%.2f", charactersPerSecond),
            "real_time_factor": String(format: "%.3f", realTimeFactor),
            "device": device,
            "os_version": osVersion
        ])
    }

    /// Track TTS synthesis failure
    public func trackTTSSynthesisFailed(  // swiftlint:disable:this function_parameter_count
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) async throws {
        try await trackEvent(.ttsSynthesisFailed, properties: [
            "synthesis_id": synthesisId,
            "model_id": modelId,
            "model_name": modelName,
            "framework": framework,
            "language": language,
            "character_count": String(characterCount),
            "processing_time_ms": String(format: "%.1f", processingTimeMs),
            "error_message": errorMessage,
            "device": device,
            "os_version": osVersion
        ])
    }

    // MARK: - Error Tracking

    /// Track error
    public func trackError(
        error: Error,
        context: String,
        additionalInfo: [String: String] = [:]
    ) async throws {
        var properties = additionalInfo
        properties["error"] = error.localizedDescription
        properties["context"] = context

        try await trackEvent(.error, properties: properties)
    }
}
