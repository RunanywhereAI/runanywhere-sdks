//
//  QuickBenchmarkResult.swift
//  RunAnywhere SDK
//
//  Quick benchmark result model
//

import Foundation

/// Quick benchmark result
public struct QuickBenchmarkResult {
    public let serviceName: String
    public let framework: LLMFramework?
    public let totalTime: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokensGenerated: Int
    public let tokensPerSecond: Double
    public let generatedText: String
}
