import Foundation

/// Real-time metrics during generation
public struct LiveGenerationMetrics: Sendable {
    public let generationId: UUID
    public let sessionId: UUID
    public let elapsedTime: TimeInterval
    public let tokensGenerated: Int
    public let currentTokensPerSecond: Double
    public let hasFirstToken: Bool
    public let timeToFirstToken: TimeInterval?

    public init(
        generationId: UUID,
        sessionId: UUID,
        elapsedTime: TimeInterval,
        tokensGenerated: Int,
        currentTokensPerSecond: Double,
        hasFirstToken: Bool,
        timeToFirstToken: TimeInterval? = nil
    ) {
        self.generationId = generationId
        self.sessionId = sessionId
        self.elapsedTime = elapsedTime
        self.tokensGenerated = tokensGenerated
        self.currentTokensPerSecond = currentTokensPerSecond
        self.hasFirstToken = hasFirstToken
        self.timeToFirstToken = timeToFirstToken
    }
}
