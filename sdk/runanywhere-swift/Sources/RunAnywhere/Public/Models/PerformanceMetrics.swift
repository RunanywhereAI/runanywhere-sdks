import Foundation

/// Detailed performance metrics
public struct PerformanceMetrics {
    /// Time spent on tokenization (milliseconds)
    public let tokenizationTimeMs: Double

    /// Time spent on inference (milliseconds)
    public let inferenceTimeMs: Double

    /// Time spent on post-processing (milliseconds)
    public let postProcessingTimeMs: Double

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Peak memory usage during generation
    public let peakMemoryUsage: Int64

    /// Queue wait time if any (milliseconds)
    public let queueWaitTimeMs: Double

    // MARK: - Thinking Mode Metrics

    /// Time to first token (milliseconds) - time from request start to first token
    public let timeToFirstTokenMs: Double?

    /// Time spent in thinking mode (milliseconds) - only if model uses thinking
    public let thinkingTimeMs: Double?

    /// Time spent generating response content after thinking (milliseconds)
    public let responseTimeMs: Double?

    /// Timestamp when thinking started (relative to generation start, in milliseconds)
    public let thinkingStartTimeMs: Double?

    /// Timestamp when thinking ended (relative to generation start, in milliseconds)
    public let thinkingEndTimeMs: Double?

    /// Timestamp when first response token arrived (relative to generation start, in milliseconds)
    public let firstResponseTokenTimeMs: Double?

    public init(
        tokenizationTimeMs: Double = 0,
        inferenceTimeMs: Double = 0,
        postProcessingTimeMs: Double = 0,
        tokensPerSecond: Double = 0,
        peakMemoryUsage: Int64 = 0,
        queueWaitTimeMs: Double = 0,
        timeToFirstTokenMs: Double? = nil,
        thinkingTimeMs: Double? = nil,
        responseTimeMs: Double? = nil,
        thinkingStartTimeMs: Double? = nil,
        thinkingEndTimeMs: Double? = nil,
        firstResponseTokenTimeMs: Double? = nil
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
