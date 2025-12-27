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
