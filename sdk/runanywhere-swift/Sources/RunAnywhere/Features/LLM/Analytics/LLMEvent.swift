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

    case modelLoadStarted(modelId: String, framework: InferenceFrameworkType = .unknown)
    case modelLoadCompleted(modelId: String, durationMs: Double, framework: InferenceFrameworkType = .unknown)
    case modelLoadFailed(modelId: String, error: String, framework: InferenceFrameworkType = .unknown)
    case modelUnloaded(modelId: String)
    case modelUnloadStarted(modelId: String)

    // MARK: - Generation

    case generationStarted(generationId: String, modelId: String, prompt: String?, framework: InferenceFrameworkType = .unknown)
    case firstToken(generationId: String, latencyMs: Double)
    case streamingUpdate(generationId: String, tokensGenerated: Int)
    case generationCompleted(
        generationId: String,
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Double,
        tokensPerSecond: Double,
        framework: InferenceFrameworkType = .unknown
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
        case .modelLoadStarted(let modelId, let framework):
            return [
                "model_id": modelId,
                "framework": framework.rawValue
            ]

        case .modelLoadCompleted(let modelId, let durationMs, let framework):
            return [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]

        case .modelLoadFailed(let modelId, let error, let framework):
            return [
                "model_id": modelId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .modelUnloadStarted(let modelId):
            return ["model_id": modelId]

        case .generationStarted(let generationId, let modelId, let prompt, let framework):
            var props = [
                "generation_id": generationId,
                "model_id": modelId,
                "framework": framework.rawValue
            ]
            if let prompt = prompt {
                props["prompt_length"] = String(prompt.count)
            }
            return props

        case .firstToken(let generationId, let latencyMs):
            return [
                "generation_id": generationId,
                "latency_ms": String(format: "%.1f", latencyMs)
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
            let framework
        ):
            return [
                "generation_id": generationId,
                "model_id": modelId,
                "input_tokens": String(inputTokens),
                "output_tokens": String(outputTokens),
                "duration_ms": String(format: "%.1f", durationMs),
                "tokens_per_second": String(format: "%.2f", tokensPerSecond),
                "framework": framework.rawValue
            ]

        case .generationFailed(let generationId, let error):
            return [
                "generation_id": generationId,
                "error": error
            ]
        }
    }
}
