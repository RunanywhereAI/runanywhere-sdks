//
//  LLMGenerationResult.swift
//  RunAnywhere SDK
//
//  Result of a text generation request
//

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

    /// Latency in milliseconds
    public let latencyMs: TimeInterval

    /// Framework used for generation
    public let framework: InferenceFramework?

    /// Tokens generated per second
    public let tokensPerSecond: Double

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
        framework: InferenceFramework? = nil,
        tokensPerSecond: Double = 0,
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
        self.structuredOutputValidation = structuredOutputValidation
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens ?? tokensUsed
    }
}
