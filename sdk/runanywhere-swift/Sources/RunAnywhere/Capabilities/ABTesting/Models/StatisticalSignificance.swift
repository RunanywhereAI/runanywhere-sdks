//
//  StatisticalSignificance.swift
//  RunAnywhere SDK
//
//  Statistical significance model
//

import Foundation

/// Statistical significance
public struct StatisticalSignificance {
    public let pValue: Double
    public let isSignificant: Bool
    public let confidenceLevel: Double
    public let effectSize: Double // Cohen's d

    public init(
        pValue: Double,
        isSignificant: Bool,
        confidenceLevel: Double,
        effectSize: Double
    ) {
        self.pValue = pValue
        self.isSignificant = isSignificant
        self.confidenceLevel = confidenceLevel
        self.effectSize = effectSize
    }
}
