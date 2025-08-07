import Foundation

/// Performance metrics for a single generation
public struct GenerationPerformance: Codable, Sendable {
    public let timeToFirstToken: TimeInterval
    public let totalGenerationTime: TimeInterval
    public let inputTokens: Int
    public let outputTokens: Int
    public let tokensPerSecond: Double
    public let modelId: String
    public let executionTarget: ExecutionTarget

    // Note: RoutingDecision is not Codable, so we store the relevant parts
    public let routingFramework: String?
    public let routingReason: String

    public init(
        timeToFirstToken: TimeInterval,
        totalGenerationTime: TimeInterval,
        inputTokens: Int,
        outputTokens: Int,
        tokensPerSecond: Double,
        modelId: String,
        executionTarget: ExecutionTarget,
        routingFramework: String? = nil,
        routingReason: String
    ) {
        self.timeToFirstToken = timeToFirstToken
        self.totalGenerationTime = totalGenerationTime
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.modelId = modelId
        self.executionTarget = executionTarget
        self.routingFramework = routingFramework
        self.routingReason = routingReason
    }

    public init(
        timeToFirstToken: TimeInterval,
        totalGenerationTime: TimeInterval,
        inputTokens: Int,
        outputTokens: Int,
        tokensPerSecond: Double,
        modelId: String,
        executionTarget: ExecutionTarget,
        routingDecision: RoutingDecision
    ) {
        self.timeToFirstToken = timeToFirstToken
        self.totalGenerationTime = totalGenerationTime
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.modelId = modelId
        self.executionTarget = executionTarget

        // Extract routing information
        switch routingDecision {
        case .onDevice(let framework, let reason):
            self.routingFramework = framework?.rawValue
            self.routingReason = reason.description
        case .cloud(let provider, let reason):
            self.routingFramework = provider
            self.routingReason = reason.description
        case .hybrid(_, let framework, let reason):
            self.routingFramework = framework?.rawValue
            self.routingReason = reason.description
        }
    }
}
