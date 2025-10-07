//
//  BenchmarkResult.swift
//  RunAnywhere SDK
//
//  Benchmark result models
//

import Foundation

/// Result from a single benchmark run
public struct SingleRunResult {
    public let serviceName: String
    public let framework: LLMFramework?
    public let promptId: String
    public let iteration: Int
    public let totalTime: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokensGenerated: Int
    public let tokensPerSecond: Double
    public let memoryUsed: Int64
    public let generatedText: String
}

/// Aggregated benchmark result
public struct BenchmarkResult: Codable {
    public let serviceName: String
    public let framework: LLMFramework?
    public let promptId: String
    public let promptCategory: PromptCategory
    public let avgTotalTime: TimeInterval
    public let avgTimeToFirstToken: TimeInterval
    public let avgTokensPerSecond: Double
    public let minTokensPerSecond: Double
    public let maxTokensPerSecond: Double
    public let stdDevTokensPerSecond: Double
    public let avgMemoryUsed: Int64
    public let iterationCount: Int
    public let error: String?

    public init(
        serviceName: String,
        framework: LLMFramework? = nil,
        promptId: String,
        promptCategory: PromptCategory = .custom,
        avgTotalTime: TimeInterval = 0,
        avgTimeToFirstToken: TimeInterval = 0,
        avgTokensPerSecond: Double = 0,
        minTokensPerSecond: Double = 0,
        maxTokensPerSecond: Double = 0,
        stdDevTokensPerSecond: Double = 0,
        avgMemoryUsed: Int64 = 0,
        iterationCount: Int = 0,
        error: String? = nil
    ) {
        self.serviceName = serviceName
        self.framework = framework
        self.promptId = promptId
        self.promptCategory = promptCategory
        self.avgTotalTime = avgTotalTime
        self.avgTimeToFirstToken = avgTimeToFirstToken
        self.avgTokensPerSecond = avgTokensPerSecond
        self.minTokensPerSecond = minTokensPerSecond
        self.maxTokensPerSecond = maxTokensPerSecond
        self.stdDevTokensPerSecond = stdDevTokensPerSecond
        self.avgMemoryUsed = avgMemoryUsed
        self.iterationCount = iterationCount
        self.error = error
    }
}
