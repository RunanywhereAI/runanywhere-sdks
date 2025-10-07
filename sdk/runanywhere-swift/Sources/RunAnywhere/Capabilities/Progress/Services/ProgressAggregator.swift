//
//  ProgressAggregator.swift
//  RunAnywhere SDK
//
//  Aggregates progress across multiple stages
//

import Foundation

/// Aggregates progress information across multiple stages
public class ProgressAggregator {

    // MARK: - Properties

    /// Weights for different stages in overall progress calculation
    private let stageWeights: [LifecycleStage: Double] = [
        .discovery: 0.05,
        .download: 0.25,
        .extraction: 0.10,
        .validation: 0.05,
        .initialization: 0.15,
        .loading: 0.30,
        .ready: 0.10
    ]

    /// Logger
    private let logger = SDKLogger(category: "ProgressAggregator")

    // MARK: - Public Methods

    /// Aggregate progress across all stages
    public func aggregate(stages: [LifecycleStage: ProgressStage]) -> AggregatedProgress {
        var totalProgress = 0.0
        var totalWeight = 0.0
        var currentStage: LifecycleStage?
        var currentStageProgress = 0.0
        var currentMessage = ""
        var estimatedTimeRemaining: TimeInterval?

        // Calculate weighted progress
        for (stage, stageInfo) in stages {
            let weight = stageWeights[stage] ?? 0.1
            totalProgress += stageInfo.progress * weight
            totalWeight += weight

            // Find current active stage (first one that's not completed and hasn't failed)
            if stageInfo.isActive && currentStage == nil {
                currentStage = stage
                currentStageProgress = stageInfo.progress
                currentMessage = stageInfo.message
                estimatedTimeRemaining = calculateTimeRemaining(for: stageInfo, allStages: stages)
            }
        }

        // Normalize progress
        let overallProgress = totalWeight > 0 ? totalProgress / totalWeight : 0

        logger.debug("Aggregated progress: \(Int(overallProgress * 100))% across \(stages.count) stages")

        return AggregatedProgress(
            overallPercentage: overallProgress,
            currentStage: currentStage,
            stageProgress: currentStageProgress,
            message: currentMessage,
            estimatedTimeRemaining: estimatedTimeRemaining,
            stages: stages
        )
    }

    /// Calculate progress for a subset of stages
    public func aggregateStages(_ stageList: [LifecycleStage], from allStages: [LifecycleStage: ProgressStage]) -> Double {
        var totalProgress = 0.0
        var totalWeight = 0.0

        for stage in stageList {
            guard let stageInfo = allStages[stage] else { continue }

            let weight = stageWeights[stage] ?? 0.1
            totalProgress += stageInfo.progress * weight
            totalWeight += weight
        }

        return totalWeight > 0 ? totalProgress / totalWeight : 0
    }

    /// Get completion percentage across all stages
    public func getCompletionPercentage(stages: [LifecycleStage: ProgressStage]) -> Double {
        let completedStages = stages.values.filter { $0.isCompleted }
        let totalStages = stages.count

        return totalStages > 0 ? Double(completedStages.count) / Double(totalStages) : 0
    }

    /// Get failure percentage across all stages
    public func getFailurePercentage(stages: [LifecycleStage: ProgressStage]) -> Double {
        let failedStages = stages.values.filter { $0.hasFailed }
        let totalStages = stages.count

        return totalStages > 0 ? Double(failedStages.count) / Double(totalStages) : 0
    }

    // MARK: - Private Methods

    private func calculateTimeRemaining(
        for currentStage: ProgressStage,
        allStages: [LifecycleStage: ProgressStage]
    ) -> TimeInterval? {

        // Estimate time for current stage
        var timeRemaining: TimeInterval = 0

        if currentStage.progress > 0 {
            let elapsed = currentStage.duration
            let estimatedTotal = elapsed / currentStage.progress
            timeRemaining += max(0, estimatedTotal - elapsed)
        }

        // Add estimated time for remaining stages
        let remainingStages = getRemainingStages(after: currentStage.stage, from: allStages)

        for stage in remainingStages {
            // Use historical average or default estimate
            let estimatedDuration = getEstimatedDuration(for: stage)
            timeRemaining += estimatedDuration
        }

        return timeRemaining > 0 ? timeRemaining : nil
    }

    private func getRemainingStages(
        after currentStage: LifecycleStage,
        from allStages: [LifecycleStage: ProgressStage]
    ) -> [LifecycleStage] {

        // Typical stage order
        let stageOrder: [LifecycleStage] = [
            .discovery, .download, .extraction, .validation, .initialization, .loading, .ready
        ]

        guard let currentIndex = stageOrder.firstIndex(of: currentStage) else {
            return []
        }

        // Return stages that come after current and aren't yet started
        return Array(stageOrder.dropFirst(currentIndex + 1)).filter { stage in
            allStages[stage] == nil
        }
    }

    private func getEstimatedDuration(for stage: LifecycleStage) -> TimeInterval {
        // Default estimates based on stage type
        switch stage {
        case .discovery:
            return 2.0
        case .download:
            return 30.0  // Highly variable
        case .extraction:
            return 5.0
        case .validation:
            return 3.0
        case .initialization:
            return 10.0
        case .loading:
            return 15.0
        case .ready:
            return 1.0
        }
    }
}
