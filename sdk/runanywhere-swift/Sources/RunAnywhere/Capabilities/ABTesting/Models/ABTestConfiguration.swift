//
//  ABTestConfiguration.swift
//  RunAnywhere SDK
//
//  A/B test configuration
//

import Foundation

/// Test configuration
public struct ABTestConfiguration {
    public let trafficSplit: Int // Percentage for variant A (0-100)
    public let sampleSize: Int
    public let maxDuration: TimeInterval
    public let minimumDetectableEffect: Double // Minimum % improvement
    public let confidenceLevel: Double

    public init(
        trafficSplit: Int = 50,
        sampleSize: Int = 1000,
        maxDuration: TimeInterval = 7 * 24 * 60 * 60, // 7 days
        minimumDetectableEffect: Double = 5.0,
        confidenceLevel: Double = 0.95
    ) {
        self.trafficSplit = trafficSplit
        self.sampleSize = sampleSize
        self.maxDuration = maxDuration
        self.minimumDetectableEffect = minimumDetectableEffect
        self.confidenceLevel = confidenceLevel
    }

    public static let `default` = ABTestConfiguration()
}
