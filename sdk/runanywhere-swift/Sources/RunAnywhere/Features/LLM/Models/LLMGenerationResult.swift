//
//  LLMGenerationResult.swift
//  RunAnywhere SDK
//
//  Result of a text generation request
//
//  🟢 BRIDGE: Thin wrapper over C++ rac_llm_result_t / rac_llm_stream_result_t
//  C++ Source: include/rac/features/llm/rac_llm_types.h
//

import CRACommons
import Foundation

/// Result of a text generation request
public struct LLMGenerationResult: Sendable {

    /// Generated text (with thinking content removed if extracted)
    public let text: String

    /// Thinking/reasoning content extracted from the response
    public let thinkingContent: String?

    /// Number of input/prompt tokens (from tokenizer)
    public let inputTokens: Int

    /// Number of tokens used (output tokens)
    public let tokensUsed: Int

    /// Model used for generation
    public let modelUsed: String

    /// Total latency in milliseconds (from start to completion)
    public let latencyMs: TimeInterval

    /// Framework used for generation (as string for flexibility)
    public let framework: String?

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Time to first token in milliseconds (only available for streaming generations)
    /// - Note: This is nil for non-streaming `generate()` calls since the entire response
    ///         is returned at once. Use `generateStream()` to get TTFT metrics.
    public let timeToFirstTokenMs: Double?

    /// Structured output validation result (if structured output was requested)
    public var structuredOutputValidation: StructuredOutputValidation?

    // MARK: - Thinking Mode Token Metrics

    /// Number of tokens used for thinking/reasoning (if model supports thinking mode)
    public let thinkingTokens: Int?

    /// Number of tokens in the actual response content (excluding thinking)
    public let responseTokens: Int

    /// Initializer
    public init(
        text: String,
        thinkingContent: String? = nil,
        inputTokens: Int = 0,
        tokensUsed: Int,
        modelUsed: String,
        latencyMs: TimeInterval,
        framework: String? = nil,
        tokensPerSecond: Double = 0,
        timeToFirstTokenMs: Double? = nil,
        structuredOutputValidation: StructuredOutputValidation? = nil,
        thinkingTokens: Int? = nil,
        responseTokens: Int? = nil
    ) {
        self.text = text
        self.thinkingContent = thinkingContent
        self.inputTokens = inputTokens
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.framework = framework
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.structuredOutputValidation = structuredOutputValidation
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens ?? tokensUsed
    }

    // MARK: - C++ Bridge (rac_llm_result_t)

    /// Initialize from C++ rac_llm_result_t (non-streaming result)
    /// - Parameters:
    ///   - cResult: The C++ result struct
    ///   - modelId: Model ID used for generation
    public init(from cResult: rac_llm_result_t, modelId: String) {
        self.init(
            text: cResult.text.map { String(cString: $0) } ?? "",
            thinkingContent: nil,
            inputTokens: Int(cResult.prompt_tokens),
            tokensUsed: Int(cResult.completion_tokens),
            modelUsed: modelId,
            latencyMs: TimeInterval(cResult.total_time_ms),
            framework: nil,
            tokensPerSecond: Double(cResult.tokens_per_second),
            timeToFirstTokenMs: cResult.time_to_first_token_ms > 0
                ? Double(cResult.time_to_first_token_ms) : nil,
            structuredOutputValidation: nil,
            thinkingTokens: nil,
            responseTokens: Int(cResult.completion_tokens)
        )
    }

    /// Initialize from C++ rac_llm_stream_result_t (streaming result)
    /// - Parameters:
    ///   - cStreamResult: The C++ streaming result struct
    ///   - modelId: Model ID used for generation
    public init(from cStreamResult: rac_llm_stream_result_t, modelId: String) {
        let metrics = cStreamResult.metrics
        self.init(
            text: cStreamResult.text.map { String(cString: $0) } ?? "",
            thinkingContent: cStreamResult.thinking_content.map { String(cString: $0) },
            inputTokens: Int(metrics.prompt_tokens),
            tokensUsed: Int(metrics.tokens_generated),
            modelUsed: modelId,
            latencyMs: TimeInterval(metrics.total_time_ms),
            framework: nil,
            tokensPerSecond: Double(metrics.tokens_per_second),
            timeToFirstTokenMs: metrics.time_to_first_token_ms > 0
                ? Double(metrics.time_to_first_token_ms) : nil,
            structuredOutputValidation: nil,
            thinkingTokens: metrics.thinking_tokens > 0 ? Int(metrics.thinking_tokens) : nil,
            responseTokens: Int(metrics.response_tokens)
        )
    }
}
