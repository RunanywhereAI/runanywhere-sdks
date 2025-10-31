import Foundation

/// Detailed performance metrics
public struct PerformanceMetrics {
    /// Time spent on tokenization (milliseconds)
    public let tokenizationTimeMs: TimeInterval

    /// Time spent on inference (milliseconds)
    public let inferenceTimeMs: TimeInterval

    /// Time spent on post-processing (milliseconds)
    public let postProcessingTimeMs: TimeInterval

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Peak memory usage during generation
    public let peakMemoryUsage: Int64

    /// Queue wait time if any (milliseconds)
    public let queueWaitTimeMs: TimeInterval

    // MARK: - Thinking Mode Metrics

    /// Time to first token (milliseconds) - time from request start to first token
    public let timeToFirstTokenMs: TimeInterval?

    /// Time spent in thinking mode (milliseconds) - only if model uses thinking
    public let thinkingTimeMs: TimeInterval?

    /// Time spent generating response content after thinking (milliseconds)
    public let responseTimeMs: TimeInterval?

    /// Timestamp when thinking started (relative to generation start, in milliseconds)
    public let thinkingStartTimeMs: TimeInterval?

    /// Timestamp when thinking ended (relative to generation start, in milliseconds)
    public let thinkingEndTimeMs: TimeInterval?

    /// Timestamp when first response token arrived (relative to generation start, in milliseconds)
    public let firstResponseTokenTimeMs: TimeInterval?

    public init(
        tokenizationTimeMs: TimeInterval = 0,
        inferenceTimeMs: TimeInterval = 0,
        postProcessingTimeMs: TimeInterval = 0,
        tokensPerSecond: Double = 0,
        peakMemoryUsage: Int64 = 0,
        queueWaitTimeMs: TimeInterval = 0,
        timeToFirstTokenMs: TimeInterval? = nil,
        thinkingTimeMs: TimeInterval? = nil,
        responseTimeMs: TimeInterval? = nil,
        thinkingStartTimeMs: TimeInterval? = nil,
        thinkingEndTimeMs: TimeInterval? = nil,
        firstResponseTokenTimeMs: TimeInterval? = nil
    ) {
        self.tokenizationTimeMs = tokenizationTimeMs
        self.inferenceTimeMs = inferenceTimeMs
        self.postProcessingTimeMs = postProcessingTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryUsage = peakMemoryUsage
        self.queueWaitTimeMs = queueWaitTimeMs
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.thinkingTimeMs = thinkingTimeMs
        self.responseTimeMs = responseTimeMs
        self.thinkingStartTimeMs = thinkingStartTimeMs
        self.thinkingEndTimeMs = thinkingEndTimeMs
        self.firstResponseTokenTimeMs = firstResponseTokenTimeMs
    }
}
