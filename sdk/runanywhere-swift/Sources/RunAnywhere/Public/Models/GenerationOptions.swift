import Foundation

/// Options for text generation
public struct RunAnywhereGenerationOptions {
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

    /// Seed for reproducible generation
    public let seed: Int?

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Token budget constraint (for cost control)
    public let tokenBudget: TokenBudget?

    /// Framework-specific options
    public let frameworkOptions: FrameworkOptions?

    /// Preferred execution target
    public let preferredExecutionTarget: ExecutionTarget?

    /// Structured output configuration (optional)
    public let structuredOutput: StructuredOutputConfig?

    /// System prompt to define AI behavior and formatting rules
    public let systemPrompt: String?

    /// Initialize generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate (default: 100)
    ///   - temperature: Sampling temperature (default: 0.7)
    ///   - topP: Top-p sampling (default: 1.0)
///   - enableRealTimeTracking: Enable real-time cost tracking (default: true)
    ///   - stopSequences: Stop generation at these sequences (default: empty)
    ///   - seed: Optional seed for reproducibility
    ///   - streamingEnabled: Enable streaming mode (default: false)
    ///   - tokenBudget: Token budget constraints
    ///   - frameworkOptions: Framework-specific options
    ///   - preferredExecutionTarget: Preferred execution target
    ///   - structuredOutput: Structured output configuration (optional)
    ///   - systemPrompt: System prompt for AI behavior (optional)
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.7,
        topP: Float = 1.0,
enableRealTimeTracking: Bool = true,
        stopSequences: [String] = [],
        seed: Int? = nil,
        streamingEnabled: Bool = false,
        tokenBudget: TokenBudget? = nil,
        frameworkOptions: FrameworkOptions? = nil,
        preferredExecutionTarget: ExecutionTarget? = nil,
        structuredOutput: StructuredOutputConfig? = nil,
        systemPrompt: String? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
self.enableRealTimeTracking = enableRealTimeTracking
        self.stopSequences = stopSequences
        self.seed = seed
        self.streamingEnabled = streamingEnabled
        self.tokenBudget = tokenBudget
        self.frameworkOptions = frameworkOptions
        self.preferredExecutionTarget = preferredExecutionTarget
        self.structuredOutput = structuredOutput
        self.systemPrompt = systemPrompt
    }
}
