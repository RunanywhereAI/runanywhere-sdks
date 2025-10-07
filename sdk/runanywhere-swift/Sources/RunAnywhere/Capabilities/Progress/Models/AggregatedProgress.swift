//
//  AggregatedProgress.swift
//  RunAnywhere SDK
//
//  Aggregated progress across multiple stages
//

import Foundation

/// Aggregated progress information across multiple stages
public struct AggregatedProgress {
    public let overallPercentage: Double
    public let currentStage: LifecycleStage?
    public let stageProgress: Double
    public let message: String
    public let estimatedTimeRemaining: TimeInterval?
    public let stages: [LifecycleStage: ProgressStage]

    public init(
        overallPercentage: Double,
        currentStage: LifecycleStage? = nil,
        stageProgress: Double = 0.0,
        message: String = "",
        estimatedTimeRemaining: TimeInterval? = nil,
        stages: [LifecycleStage: ProgressStage] = [:]
    ) {
        self.overallPercentage = overallPercentage
        self.currentStage = currentStage
        self.stageProgress = stageProgress
        self.message = message
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.stages = stages
    }

    /// Convert to OverallProgress for backward compatibility
    public var asOverallProgress: OverallProgress {
        return OverallProgress(
            percentage: overallPercentage,
            currentStage: currentStage,
            stageProgress: stageProgress,
            message: message,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
    }

    /// Get progress for a specific stage
    public func progressForStage(_ stage: LifecycleStage) -> ProgressStage? {
        return stages[stage]
    }

    /// Get completed stages
    public var completedStages: [LifecycleStage] {
        return stages.compactMap { key, value in
            value.isCompleted ? key : nil
        }.sorted()
    }

    /// Get failed stages
    public var failedStages: [LifecycleStage] {
        return stages.compactMap { key, value in
            value.hasFailed ? key : nil
        }.sorted()
    }

    /// Get active stages
    public var activeStages: [LifecycleStage] {
        return stages.compactMap { key, value in
            value.isActive ? key : nil
        }.sorted()
    }
}
