//
//  ModelLoadableEvent.swift
//  RunAnywhere SDK
//
//  Protocol for events that represent model lifecycle operations.
//  Provides shared functionality for model load/unload events across LLM, STT, TTS, VAD.
//

import Foundation

// MARK: - Model Lifecycle Event Data

/// Shared data structure for model lifecycle events.
/// Reduces duplication across LLM, STT, TTS, VAD event types.
public struct ModelLifecycleData: Sendable {
    public let modelId: String
    public let modelSizeBytes: Int64
    public let framework: InferenceFramework
    public let durationMs: Double?
    public let error: SDKError?
    public let success: Bool

    /// Create data for model load started event
    public static func loadStarted(
        modelId: String,
        modelSizeBytes: Int64 = 0,
        framework: InferenceFramework = .unknown
    ) -> ModelLifecycleData {
        ModelLifecycleData(
            modelId: modelId,
            modelSizeBytes: modelSizeBytes,
            framework: framework,
            durationMs: nil,
            error: nil,
            success: true
        )
    }

    /// Create data for model load completed event
    public static func loadCompleted(
        modelId: String,
        durationMs: Double,
        modelSizeBytes: Int64 = 0,
        framework: InferenceFramework = .unknown
    ) -> ModelLifecycleData {
        ModelLifecycleData(
            modelId: modelId,
            modelSizeBytes: modelSizeBytes,
            framework: framework,
            durationMs: durationMs,
            error: nil,
            success: true
        )
    }

    /// Create data for model load failed event
    public static func loadFailed(
        modelId: String,
        error: SDKError,
        framework: InferenceFramework = .unknown
    ) -> ModelLifecycleData {
        ModelLifecycleData(
            modelId: modelId,
            modelSizeBytes: 0,
            framework: framework,
            durationMs: nil,
            error: error,
            success: false
        )
    }

    /// Create data for model unloaded event
    public static func unloaded(modelId: String) -> ModelLifecycleData {
        ModelLifecycleData(
            modelId: modelId,
            modelSizeBytes: 0,
            framework: .unknown,
            durationMs: nil,
            error: nil,
            success: true
        )
    }

    /// Convert to string properties for analytics
    public func toProperties(includeSuccess: Bool = false) -> [String: String] {
        var props: [String: String] = [
            "model_id": modelId,
            "framework": framework.rawValue
        ]

        if modelSizeBytes > 0 {
            props["model_size_bytes"] = String(modelSizeBytes)
        }

        if let duration = durationMs {
            props["processing_time_ms"] = String(format: "%.1f", duration)
        }

        if includeSuccess {
            props["success"] = String(success)
        }

        if let error = error {
            props.merge(error.telemetryProperties) { _, new in new }
        }

        return props
    }

    /// Convert to TelemetryProperties
    public func toTelemetryProperties() -> TelemetryProperties {
        TelemetryProperties(
            modelId: modelId,
            framework: framework.rawValue,
            processingTimeMs: durationMs,
            success: success,
            errorMessage: error?.message,
            errorCode: error?.code.rawValue,
            modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
        )
    }
}

// MARK: - TelemetryProperties Dictionary Conversion

extension TelemetryProperties {
    /// Convert TelemetryProperties to a string dictionary for analytics.
    /// This provides a default implementation that events can use instead of
    /// manually building the properties dictionary.
    public func toDictionary() -> [String: String] {
        var props: [String: String] = [:]

        // Build properties using helper to reduce cyclomatic complexity
        addModelInfoProperties(to: &props)
        addCommonMetricProperties(to: &props)
        addLLMProperties(to: &props)
        addSTTProperties(to: &props)
        addTTSProperties(to: &props)
        addVADProperties(to: &props)

        return props
    }

    // MARK: - Property Group Helpers

    private func addModelInfoProperties(to props: inout [String: String]) {
        if let modelId = modelId { props["model_id"] = modelId }
        if let modelName = modelName { props["model_name"] = modelName }
        if let framework = framework { props["framework"] = framework }
        if let modelSizeBytes = modelSizeBytes { props["model_size_bytes"] = String(modelSizeBytes) }
    }

    private func addCommonMetricProperties(to props: inout [String: String]) {
        if let processingTimeMs = processingTimeMs {
            props["processing_time_ms"] = String(format: "%.1f", processingTimeMs)
        }
        if let durationMs = durationMs {
            props["duration_ms"] = String(format: "%.1f", durationMs)
        }
        if let success = success { props["success"] = String(success) }
        if let errorMessage = errorMessage { props["error_message"] = errorMessage }
        if let errorCode = errorCode { props["error_code"] = errorCode }
    }

    private func addLLMProperties(to props: inout [String: String]) {
        if let inputTokens = inputTokens { props["input_tokens"] = String(inputTokens) }
        if let outputTokens = outputTokens { props["output_tokens"] = String(outputTokens) }
        if let totalTokens = totalTokens { props["total_tokens"] = String(totalTokens) }
        if let tokensPerSecond = tokensPerSecond {
            props["tokens_per_second"] = String(format: "%.2f", tokensPerSecond)
        }
        if let timeToFirstTokenMs = timeToFirstTokenMs {
            props["time_to_first_token_ms"] = String(format: "%.1f", timeToFirstTokenMs)
        }
        if let generationTimeMs = generationTimeMs {
            props["generation_time_ms"] = String(format: "%.1f", generationTimeMs)
        }
        if let contextLength = contextLength { props["context_length"] = String(contextLength) }
        if let temperature = temperature {
            props["temperature"] = String(format: "%.2f", temperature)
        }
        if let maxTokens = maxTokens { props["max_tokens"] = String(maxTokens) }
        if let isStreaming = isStreaming { props["is_streaming"] = String(isStreaming) }
        if let generationId = generationId { props["generation_id"] = generationId }
    }

    private func addSTTProperties(to props: inout [String: String]) {
        if let audioDurationMs = audioDurationMs {
            props["audio_duration_ms"] = String(format: "%.1f", audioDurationMs)
        }
        if let realTimeFactor = realTimeFactor {
            props["real_time_factor"] = String(format: "%.3f", realTimeFactor)
        }
        if let wordCount = wordCount { props["word_count"] = String(wordCount) }
        if let confidence = confidence {
            props["confidence"] = String(format: "%.3f", confidence)
        }
        if let language = language { props["language"] = language }
        if let transcriptionId = transcriptionId { props["transcription_id"] = transcriptionId }
    }

    private func addTTSProperties(to props: inout [String: String]) {
        if let characterCount = characterCount { props["character_count"] = String(characterCount) }
        if let charactersPerSecond = charactersPerSecond {
            props["chars_per_second"] = String(format: "%.2f", charactersPerSecond)
        }
        if let audioSizeBytes = audioSizeBytes { props["audio_size_bytes"] = String(audioSizeBytes) }
        if let sampleRate = sampleRate { props["sample_rate"] = String(sampleRate) }
        if let voice = voice { props["voice"] = voice }
        if let outputDurationMs = outputDurationMs {
            props["audio_duration_ms"] = String(format: "%.1f", outputDurationMs)
        }
        if let synthesisId = synthesisId { props["synthesis_id"] = synthesisId }
    }

    private func addVADProperties(to props: inout [String: String]) {
        if let speechDurationMs = speechDurationMs {
            props["speech_duration_ms"] = String(format: "%.1f", speechDurationMs)
        }
    }
}

// MARK: - Default Properties Implementation

/// Extension providing default properties implementation based on telemetryProperties.
/// Events can use this to avoid duplicating property conversion logic.
public extension TelemetryEventProperties {
    /// Default implementation that derives properties from telemetryProperties.
    /// Events can override this if they need custom formatting.
    var derivedProperties: [String: String] {
        telemetryProperties.toDictionary()
    }
}
