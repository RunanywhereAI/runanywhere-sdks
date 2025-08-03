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

    public init(
        tokenizationTimeMs: TimeInterval = 0,
        inferenceTimeMs: TimeInterval = 0,
        postProcessingTimeMs: TimeInterval = 0,
        tokensPerSecond: Double = 0,
        peakMemoryUsage: Int64 = 0,
        queueWaitTimeMs: TimeInterval = 0
    ) {
        self.tokenizationTimeMs = tokenizationTimeMs
        self.inferenceTimeMs = inferenceTimeMs
        self.postProcessingTimeMs = postProcessingTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryUsage = peakMemoryUsage
        self.queueWaitTimeMs = queueWaitTimeMs
    }
}
