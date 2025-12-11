//
//  LLMOutput.swift
//  RunAnywhere SDK
//
//  Output model for LLM generation
//

import Foundation

/// Output from Language Model generation
public struct LLMOutput: ComponentOutput, Sendable {

    /// Generated text
    public let text: String

    /// Token usage statistics
    public let tokenUsage: TokenUsage

    /// Generation metadata
    public let metadata: GenerationMetadata

    /// Finish reason
    public let finishReason: FinishReason

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        text: String,
        tokenUsage: TokenUsage,
        metadata: GenerationMetadata,
        finishReason: FinishReason,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.tokenUsage = tokenUsage
        self.metadata = metadata
        self.finishReason = finishReason
        self.timestamp = timestamp
    }
}

/// Token usage information
public struct TokenUsage: Sendable {

    public let promptTokens: Int
    public let completionTokens: Int

    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Generation metadata
public struct GenerationMetadata: Sendable {

    public let modelId: String
    public let temperature: Float
    public let generationTime: TimeInterval
    public let tokensPerSecond: Double?

    public init(
        modelId: String,
        temperature: Float,
        generationTime: TimeInterval,
        tokensPerSecond: Double? = nil
    ) {
        self.modelId = modelId
        self.temperature = temperature
        self.generationTime = generationTime
        self.tokensPerSecond = tokensPerSecond
    }
}

/// Reason for generation completion
public enum FinishReason: String, Sendable {
    case completed = "completed"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case contentFilter = "content_filter"
    case error = "error"
}
