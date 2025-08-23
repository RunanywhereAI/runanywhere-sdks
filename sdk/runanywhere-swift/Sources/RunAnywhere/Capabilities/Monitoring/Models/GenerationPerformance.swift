//
//  GenerationPerformance.swift
//  RunAnywhere SDK
//
//  Performance metrics for generation operations
//

import Foundation

/// Import ExecutionTarget from routing models
extension ExecutionTarget {
    // Extend with monitoring-specific functionality if needed
}

/// Performance metrics for a generation operation
public struct GenerationPerformance {

    // MARK: - Properties

    /// Time to first token in seconds
    public let timeToFirstToken: TimeInterval

    /// Total generation time in seconds
    public let totalGenerationTime: TimeInterval

    /// Number of input tokens
    public let inputTokens: Int

    /// Number of output tokens
    public let outputTokens: Int

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Model identifier
    public let modelId: String

    /// Execution target (on-device or cloud)
    public let executionTarget: ExecutionTarget

    /// Routing framework used
    public let routingFramework: String

    /// Reason for routing decision
    public let routingReason: String

    /// Timestamp
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        timeToFirstToken: TimeInterval,
        totalGenerationTime: TimeInterval,
        inputTokens: Int,
        outputTokens: Int,
        tokensPerSecond: Double,
        modelId: String,
        executionTarget: ExecutionTarget,
        routingFramework: String,
        routingReason: String,
        timestamp: Date = Date()
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
        self.timestamp = timestamp
    }
}
