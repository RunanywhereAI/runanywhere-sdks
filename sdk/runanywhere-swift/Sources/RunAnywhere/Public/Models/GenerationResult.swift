import Foundation

/// Container for streaming generation with metrics
/// Provides both the token stream and a task that resolves to final metrics
public struct StreamingResult {
    /// Stream of tokens as they are generated
    public let stream: AsyncThrowingStream<String, Error>

    /// Task that completes with final generation result including metrics
    /// Resolves after streaming is complete
    public let result: Task<GenerationResult, Error>

    public init(
        stream: AsyncThrowingStream<String, Error>,
        result: Task<GenerationResult, Error>
    ) {
        self.stream = stream
        self.result = result
    }
}

/// Result of a text generation request
public struct GenerationResult {
    /// Generated text (with thinking content removed if extracted)
    public let text: String

    /// Thinking/reasoning content extracted from the response
    public let thinkingContent: String?

    /// Number of tokens used
    public let tokensUsed: Int

    /// Model used for generation
    public let modelUsed: String

    /// Latency in milliseconds
    public let latencyMs: TimeInterval

    /// Execution target (device/cloud/hybrid)
    public let executionTarget: ExecutionTarget

    /// Amount saved by using on-device execution
    public let savedAmount: Double

    /// Framework used for generation (if on-device)
    public let framework: LLMFramework?

    /// Hardware acceleration used
    public let hardwareUsed: HardwareAcceleration

    /// Memory used during generation (in bytes)
    public let memoryUsed: Int64

    /// Detailed performance metrics
    public let performanceMetrics: PerformanceMetrics

    /// Structured output validation result (if structured output was requested)
    public var structuredOutputValidation: StructuredOutputValidation?

    // MARK: - Thinking Mode Token Metrics

    /// Number of tokens used for thinking/reasoning (if model supports thinking mode)
    public let thinkingTokens: Int?

    /// Number of tokens in the actual response content (excluding thinking)
    public let responseTokens: Int

    /// Initializer
    internal init(
        text: String,
        thinkingContent: String? = nil,
        tokensUsed: Int,
        modelUsed: String,
        latencyMs: TimeInterval,
        executionTarget: ExecutionTarget,
        savedAmount: Double,
        framework: LLMFramework? = nil,
        hardwareUsed: HardwareAcceleration = .cpu,
        memoryUsed: Int64 = 0,
        performanceMetrics: PerformanceMetrics,
        structuredOutputValidation: StructuredOutputValidation? = nil,
        thinkingTokens: Int? = nil,
        responseTokens: Int? = nil
    ) {
        self.text = text
        self.thinkingContent = thinkingContent
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.executionTarget = executionTarget
        self.savedAmount = savedAmount
        self.framework = framework
        self.hardwareUsed = hardwareUsed
        self.memoryUsed = memoryUsed
        self.performanceMetrics = performanceMetrics
        self.structuredOutputValidation = structuredOutputValidation
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens ?? tokensUsed
    }
}
