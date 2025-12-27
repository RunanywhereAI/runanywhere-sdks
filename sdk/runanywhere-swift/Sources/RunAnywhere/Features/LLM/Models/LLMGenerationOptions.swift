//
//  LLMGenerationOptions.swift
//  RunAnywhere SDK
//
//  Options for text generation
//

import Foundation

/// Options for text generation
public struct LLMGenerationOptions: Sendable {

    /// Maximum number of tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Float

    /// Top-p sampling parameter
    public let topP: Float

    /// Stop sequences
    public let stopSequences: [String]

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Preferred framework for generation
    public let preferredFramework: InferenceFramework?

    /// Structured output configuration (optional)
    public let structuredOutput: StructuredOutputConfig?

    /// System prompt to define AI behavior and formatting rules
    public let systemPrompt: String?

    /// Initialize generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate (default: 100)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - topP: Top-p sampling (default: 1.0)
    ///   - stopSequences: Stop generation at these sequences (default: empty)
    ///   - streamingEnabled: Enable streaming mode (default: false)
    ///   - preferredFramework: Preferred framework adapter (optional)
    ///   - structuredOutput: Structured output configuration (optional)
    ///   - systemPrompt: System prompt for AI behavior (optional)
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.8,
        topP: Float = 1.0,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredFramework: InferenceFramework? = nil,
        structuredOutput: StructuredOutputConfig? = nil,
        systemPrompt: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.streamingEnabled = streamingEnabled
        self.preferredFramework = preferredFramework
        self.structuredOutput = structuredOutput
        self.systemPrompt = systemPrompt
    }
}
