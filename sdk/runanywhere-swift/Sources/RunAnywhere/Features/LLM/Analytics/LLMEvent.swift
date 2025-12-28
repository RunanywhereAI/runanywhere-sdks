//
//  LLMEvent.swift
//  RunAnywhere SDK
//
//  All LLM-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//
//  Note: LLMEvent conforms to TelemetryEventProperties for strongly typed analytics.
//  This avoids string conversion/parsing and enables compile-time type checking.
//

import Foundation

// MARK: - LLM Event

/// All LLM-related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...))
/// ```
///
/// LLMEvent provides strongly typed properties via `telemetryProperties`.
/// This enables:
/// - Type safety at compile time
/// - No string parsing for analytics
/// - Validation guardrails (e.g., tokensPerSecond > 0)
public enum LLMEvent: SDKEvent, TelemetryEventProperties {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    case modelLoadFailed(modelId: String, error: SDKError, framework: InferenceFramework = .unknown)
    case modelUnloaded(modelId: String)
    case modelUnloadStarted(modelId: String)

    // MARK: - Generation

    /// Generation started event
    /// - Parameters:
    ///   - isStreaming: true for generateStream(), false for generate()
    case generationStarted(
        generationId: String,
        modelId: String,
        prompt: String?,
        isStreaming: Bool = false,
        framework: InferenceFramework = .unknown
    )

    /// First token received (only applicable for streaming generation)
    case firstToken(generationId: String, modelId: String, timeToFirstTokenMs: Double, framework: InferenceFramework = .unknown)

    /// Streaming update (only applicable for streaming generation)
    case streamingUpdate(generationId: String, tokensGenerated: Int)

    /// Generation completed
    /// - Parameters:
    ///   - isStreaming: true for generateStream(), false for generate()
    ///   - timeToFirstTokenMs: Time to first token in ms (only for streaming, nil for non-streaming)
    case generationCompleted(
        generationId: String,
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Double,
        tokensPerSecond: Double,
        isStreaming: Bool = false,
        timeToFirstTokenMs: Double? = nil,
        framework: InferenceFramework = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    )
    case generationFailed(generationId: String, error: SDKError)

    // MARK: - SDKEvent Conformance

    public var type: String {
        switch self {
        case .modelLoadStarted: return "llm_model_load_started"
        case .modelLoadCompleted: return "llm_model_load_completed"
        case .modelLoadFailed: return "llm_model_load_failed"
        case .modelUnloaded: return "llm_model_unloaded"
        case .modelUnloadStarted: return "llm_model_unload_started"
        case .generationStarted: return "llm_generation_started"
        case .firstToken: return "llm_first_token"
        case .streamingUpdate: return "llm_streaming_update"
        case .generationCompleted: return "llm_generation_completed"
        case .generationFailed: return "llm_generation_failed"
        }
    }

    public var category: EventCategory { .llm }

    public var destination: EventDestination {
        switch self {
        case .streamingUpdate:
            // Streaming updates are too chatty for public API
            return .analyticsOnly
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        // Use derived properties from telemetryProperties for consistency
        // This eliminates duplicate property conversion logic
        telemetryProperties.toDictionary()
    }

    // MARK: - TelemetryEventProperties Conformance

    /// Strongly typed telemetry properties - no string conversion needed.
    /// These values are used directly by TelemetryEventPayload.
    public var telemetryProperties: TelemetryProperties {
        switch self {
        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadFailed(let modelId, let error, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue
            )

        case .modelUnloaded(let modelId):
            return TelemetryProperties(modelId: modelId)

        case .modelUnloadStarted(let modelId):
            return TelemetryProperties(modelId: modelId)

        case .generationStarted(let generationId, let modelId, _, let isStreaming, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                isStreaming: isStreaming,
                generationId: generationId
            )

        case .firstToken(let generationId, let modelId, let timeToFirstTokenMs, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                timeToFirstTokenMs: timeToFirstTokenMs,
                generationId: generationId
            )

        case .streamingUpdate(let generationId, let tokensGenerated):
            return TelemetryProperties(
                outputTokens: tokensGenerated,
                generationId: generationId
            )

        case .generationCompleted(
            let generationId,
            let modelId,
            let inputTokens,
            let outputTokens,
            let durationMs,
            let tokensPerSecond,
            let isStreaming,
            let timeToFirstTokenMs,
            let framework,
            let temperature,
            let maxTokens,
            let contextLength
        ):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: inputTokens + outputTokens,
                tokensPerSecond: tokensPerSecond,
                timeToFirstTokenMs: timeToFirstTokenMs,
                generationTimeMs: durationMs,
                contextLength: contextLength,
                temperature: temperature.map { Double($0) },
                maxTokens: maxTokens,
                isStreaming: isStreaming,
                generationId: generationId
            )

        case .generationFailed(let generationId, let error):
            return TelemetryProperties(
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue,
                generationId: generationId
            )
        }
    }
}
