//
//  LLMStreamingResult.swift
//  RunAnywhere SDK
//
//  Streaming generation result container
//

import Foundation

/// Container for streaming generation with metrics
/// Provides both the token stream and a task that resolves to final metrics
public struct LLMStreamingResult: Sendable {

    /// Stream of tokens as they are generated
    public let stream: AsyncThrowingStream<String, Error>

    /// Task that completes with final generation result including metrics
    /// Resolves after streaming is complete
    public let result: Task<LLMGenerationResult, Error>

    public init(
        stream: AsyncThrowingStream<String, Error>,
        result: Task<LLMGenerationResult, Error>
    ) {
        self.stream = stream
        self.result = result
    }
}

/// Token type for streaming
public enum TokenType: Sendable {
    /// Token is part of model's thinking/reasoning
    case thinking
    /// Token is part of the actual response
    case content
}

/// Represents a streaming token
public struct StreamingToken: Sendable {

    public let text: String
    public let tokenIndex: Int
    public let isLast: Bool
    public let timestamp: Date
    public let type: TokenType

    public init(
        text: String,
        tokenIndex: Int,
        isLast: Bool,
        timestamp: Date,
        type: TokenType = .content
    ) {
        self.text = text
        self.tokenIndex = tokenIndex
        self.isLast = isLast
        self.timestamp = timestamp
        self.type = type
    }
}

/// Result of splitting token counts between thinking and response content
public struct TokenCountResult: Sendable {

    public let thinkingTokens: Int?
    public let responseTokens: Int
    public let totalTokens: Int

    public init(thinkingTokens: Int?, responseTokens: Int, totalTokens: Int) {
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens
        self.totalTokens = totalTokens
    }
}
