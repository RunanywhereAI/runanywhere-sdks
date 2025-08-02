import Foundation

/// Simplified performance metrics
public struct PerformanceMetrics {
    /// Total duration in seconds
    public let totalDuration: TimeInterval

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Time to first token
    public let timeToFirstToken: TimeInterval?

    public init(
        totalDuration: TimeInterval,
        tokensPerSecond: Double,
        timeToFirstToken: TimeInterval? = nil
    ) {
        self.totalDuration = totalDuration
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstToken = timeToFirstToken
    }
}
