//
//  MemoryRecommendation.swift
//  RunAnywhere SDK
//
//  Memory optimization recommendations
//

import Foundation

/// Memory optimization recommendation
public struct MemoryRecommendation {
    /// Type of recommendation
    public let type: RecommendationType

    /// Severity level
    public let severity: RecommendationSeverity

    /// Human-readable message
    public let message: String

    /// Recommended action to take
    public let action: RecommendedAction

    public init(
        type: RecommendationType,
        severity: RecommendationSeverity,
        message: String,
        action: RecommendedAction
    ) {
        self.type = type
        self.severity = severity
        self.message = message
        self.action = action
    }
}

/// Types of memory recommendations
public enum RecommendationType {
    case highMemoryUsage
    case memoryLeak
    case fragmentation
    case inefficientAllocation
}

/// Recommendation severity levels
public enum RecommendationSeverity {
    case info
    case warning
    case critical
}

/// Recommended actions
public enum RecommendedAction {
    case unloadModels
    case restartApp
    case compactMemory
    case optimizeAllocations
}
