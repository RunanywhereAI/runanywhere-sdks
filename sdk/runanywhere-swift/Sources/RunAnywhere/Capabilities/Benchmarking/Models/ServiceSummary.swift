//
//  ServiceSummary.swift
//  RunAnywhere SDK
//
//  Service performance summary
//

import Foundation

/// Service performance summary
public struct ServiceSummary: Codable {
    public let serviceName: String
    public let framework: LLMFramework?
    public let averageTokensPerSecond: Double
    public let averageMemoryUsage: Int64
    public let successRate: Double
    public let testCount: Int
}
