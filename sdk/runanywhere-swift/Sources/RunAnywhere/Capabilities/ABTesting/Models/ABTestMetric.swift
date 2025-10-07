//
//  ABTestMetric.swift
//  RunAnywhere SDK
//
//  A/B test metric types
//

import Foundation

/// Test metric types
public enum ABTestMetric {
    case tokensPerSecond(Double)
    case timeToFirstToken(TimeInterval)
    case memoryUsage(Int64)
    case userSatisfaction(Int) // 1-5 rating
    case errorRate(Double) // 0-1

    public var value: Double {
        switch self {
        case .tokensPerSecond(let value):
            return value
        case .timeToFirstToken(let value):
            return value
        case .memoryUsage(let value):
            return Double(value)
        case .userSatisfaction(let value):
            return Double(value)
        case .errorRate(let value):
            return value
        }
    }

    public var metricType: MetricType {
        switch self {
        case .tokensPerSecond:
            return .tokensPerSecond
        case .timeToFirstToken:
            return .timeToFirstToken
        case .memoryUsage:
            return .memoryUsage
        case .userSatisfaction:
            return .userSatisfaction
        case .errorRate:
            return .errorRate
        }
    }
}

/// Metric type identifier
public enum MetricType {
    case tokensPerSecond
    case timeToFirstToken
    case memoryUsage
    case userSatisfaction
    case errorRate
}
