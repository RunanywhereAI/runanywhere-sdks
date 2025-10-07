//
//  GenerationSummary.swift
//  RunAnywhere SDK
//
//  Generation performance summary
//

import Foundation

/// Generation performance summary
public struct GenerationSummary {
    /// Unique identifier for this generation
    public let id: UUID

    /// Framework used for generation
    public let framework: LLMFramework

    /// Model name
    public let modelName: String

    /// Total time taken for generation
    public let totalTime: TimeInterval

    /// Time to first token
    public let timeToFirstToken: TimeInterval

    /// Total number of tokens generated
    public let tokenCount: Int

    /// Tokens per second rate
    public let tokensPerSecond: Double

    /// Memory used during generation
    public let memoryUsed: Int64

    public init(
        id: UUID,
        framework: LLMFramework,
        modelName: String,
        totalTime: TimeInterval,
        timeToFirstToken: TimeInterval,
        tokenCount: Int,
        tokensPerSecond: Double,
        memoryUsed: Int64
    ) {
        self.id = id
        self.framework = framework
        self.modelName = modelName
        self.totalTime = totalTime
        self.timeToFirstToken = timeToFirstToken
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.memoryUsed = memoryUsed
    }
}
