import Foundation

/// Adapter to convert between SDK GenerationResult and Analytics-compatible structures
extension GenerationService {

    /// Convert SDK GenerationResult to analytics-compatible structure
    internal func createAnalyticsResult(
        from sdkResult: GenerationResult,
        loadedModel: LoadedModel
    ) -> (result: AnalyticsGenerationResult, metrics: GenerationMetrics, cost: GenerationCost) {

        // Create metrics from SDK result
        let metrics = GenerationMetrics(
            inputTokens: sdkResult.tokensUsed / 2, // Approximate input tokens as half of total
            outputTokens: sdkResult.tokensUsed / 2, // Approximate output tokens as half of total
            tokensPerSecond: sdkResult.performanceMetrics.tokensPerSecond,
            totalTime: sdkResult.latencyMs / 1000.0 // Convert ms to seconds
        )

        // Create cost from SDK result
        let cost = GenerationCost(
            estimated: sdkResult.savedAmount, // Use saved amount as estimated
            actual: 0.0, // On-device has no actual cost
            saved: sdkResult.savedAmount
        )

        // Create analytics-compatible result
        let analyticsResult = AnalyticsGenerationResult(
            text: sdkResult.text,
            model: loadedModel,
            executionTarget: sdkResult.executionTarget,
            metrics: metrics,
            cost: cost
        )

        return (analyticsResult, metrics, cost)
    }
}

/// Analytics-compatible generation result
public struct AnalyticsGenerationResult {
    let text: String
    let model: LoadedModel
    let executionTarget: ExecutionTarget
    let metrics: GenerationMetrics
    let cost: GenerationCost
}

/// Generation metrics for analytics
public struct GenerationMetrics: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let tokensPerSecond: Double
    public let totalTime: TimeInterval

    public init(
        inputTokens: Int,
        outputTokens: Int,
        tokensPerSecond: Double,
        totalTime: TimeInterval
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.tokensPerSecond = tokensPerSecond
        self.totalTime = totalTime
    }
}

/// Generation cost tracking
public struct GenerationCost: Codable, Sendable {
    public let estimated: Double
    public let actual: Double
    public let saved: Double

    public init(
        estimated: Double,
        actual: Double,
        saved: Double
    ) {
        self.estimated = estimated
        self.actual = actual
        self.saved = saved
    }
}
