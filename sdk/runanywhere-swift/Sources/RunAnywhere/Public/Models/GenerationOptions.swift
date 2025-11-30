import Foundation

/// Options for text generation
public struct RunAnywhereGenerationOptions: Sendable {
    /// Maximum number of tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling (0.0 - 1.0)
    public let temperature: Float

    /// Top-p sampling parameter
    public let topP: Float

/// Enable real-time tracking for cost dashboard
    public let enableRealTimeTracking: Bool

    /// Stop sequences
    public let stopSequences: [String]

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Preferred execution target
    public let preferredExecutionTarget: ExecutionTarget?

    /// Preferred framework for generation (NEW)
    public let preferredFramework: LLMFramework?

    /// Structured output configuration (optional)
    public let structuredOutput: StructuredOutputConfig?

    /// System prompt to define AI behavior and formatting rules
    public let systemPrompt: String?

    /// Initialize generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate (default: 100)
    ///   - temperature: Sampling temperature (default: 0.8, matches LLM.swift)
    ///   - topP: Top-p sampling (default: 1.0)
///   - enableRealTimeTracking: Enable real-time cost tracking (default: true)
    ///   - stopSequences: Stop generation at these sequences (default: empty)
    ///   - streamingEnabled: Enable streaming mode (default: false)
    ///   - preferredExecutionTarget: Preferred execution target
    ///   - preferredFramework: Preferred framework adapter (optional)
    ///   - structuredOutput: Structured output configuration (optional)
    ///   - systemPrompt: System prompt for AI behavior (optional)
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.8,
        topP: Float = 1.0,
enableRealTimeTracking: Bool = true,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredExecutionTarget: ExecutionTarget? = nil,
        preferredFramework: LLMFramework? = nil,
        structuredOutput: StructuredOutputConfig? = nil,
        systemPrompt: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
self.enableRealTimeTracking = enableRealTimeTracking
        self.stopSequences = stopSequences
        self.streamingEnabled = streamingEnabled
        self.preferredExecutionTarget = preferredExecutionTarget
        self.preferredFramework = preferredFramework
        self.structuredOutput = structuredOutput
        self.systemPrompt = systemPrompt
    }
}
