//
//  LLMEvent.swift
//  RunAnywhere SDK
//
//  All LLM-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//

import Foundation

// MARK: - LLM Event

/// All LLM-related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...))
/// ```
public enum LLMEvent: SDKEvent {

    // MARK: - Model Lifecycle

    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(modelId: String, error: String, framework: InferenceFrameworkType = .unknown)
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
        framework: InferenceFrameworkType = .unknown
    )

    /// First token received (only applicable for streaming generation)
    case firstToken(generationId: String, modelId: String, timeToFirstTokenMs: Double, framework: InferenceFrameworkType = .unknown)

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
        framework: InferenceFrameworkType = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    )
    case generationFailed(generationId: String, error: String)

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
        switch self {
        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "processing_time_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue,
                "success": "true"
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadFailed(let modelId, let error, let framework):
            return [
                "model_id": modelId,
                "error_message": error,
                "framework": framework.rawValue,
                "success": "false"
            ]

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .modelUnloadStarted(let modelId):
            return ["model_id": modelId]

        case .generationStarted(let generationId, let modelId, let prompt, let isStreaming, let framework):
            var props = [
                "generation_id": generationId,
                "model_id": modelId,
                "is_streaming": String(isStreaming),
                "framework": framework.rawValue
            ]
            if let prompt = prompt {
                props["prompt_length"] = String(prompt.count)
            }
            return props

        case .firstToken(let generationId, let modelId, let timeToFirstTokenMs, let framework):
            return [
                "generation_id": generationId,
                "model_id": modelId,
                "time_to_first_token_ms": String(format: "%.1f", timeToFirstTokenMs),
                "framework": framework.rawValue
            ]

        case .streamingUpdate(let generationId, let tokensGenerated):
            return [
                "generation_id": generationId,
                "tokens_generated": String(tokensGenerated)
            ]

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
            var props = [
                "generation_id": generationId,
                "model_id": modelId,
                "input_tokens": String(inputTokens),
                "output_tokens": String(outputTokens),
                "total_tokens": String(inputTokens + outputTokens),
                "processing_time_ms": String(format: "%.1f", durationMs),
                "generation_time_ms": String(format: "%.1f", durationMs),
                "tokens_per_second": String(format: "%.2f", tokensPerSecond),
                "is_streaming": String(isStreaming),
                "framework": framework.rawValue,
                "success": "true"
            ]
            if let ttft = timeToFirstTokenMs {
                props["time_to_first_token_ms"] = String(format: "%.1f", ttft)
            }
            if let temp = temperature {
                props["temperature"] = String(format: "%.2f", temp)
            }
            if let maxTok = maxTokens {
                props["max_tokens"] = String(maxTok)
            }
            if let ctx = contextLength {
                props["context_length"] = String(ctx)
            }
            return props

        case .generationFailed(let generationId, let error):
            return [
                "generation_id": generationId,
                "error_message": error,
                "success": "false"
            ]
        }
    }
}
