import Foundation

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
        structuredOutputValidation: StructuredOutputValidation? = nil
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
    }
}
