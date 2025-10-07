//
//  StageManager.swift
//  RunAnywhere SDK
//
//  Manages individual progress stages
//

import Foundation

/// Manages individual progress stages with thread safety
public class StageManager {

    // MARK: - Properties

    /// All stages indexed by lifecycle stage
    private var stages: [LifecycleStage: ProgressStage] = [:]

    /// Thread safety lock
    private let lock = NSLock()

    /// Stage duration history for time estimation
    private var stageDurationHistory: [LifecycleStage: [TimeInterval]] = [:]

    /// Logger
    private let logger = SDKLogger(category: "StageManager")

    // MARK: - Public Methods

    /// Start a new stage
    public func startStage(_ stage: LifecycleStage) {
        lock.lock()
        defer { lock.unlock() }

        stages[stage] = ProgressStage(stage: stage)
        logger.debug("Started stage: \(stage)")
    }

    /// Update stage progress
    public func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String?) {
        lock.lock()
        defer { lock.unlock() }

        guard var stageInfo = stages[stage] else {
            logger.warning("Attempted to update non-existent stage: \(stage)")
            return
        }

        stageInfo.progress = min(1.0, max(0.0, progress))
        if let message = message {
            stageInfo.message = message
        }

        stages[stage] = stageInfo
    }

    /// Complete a stage
    public func completeStage(_ stage: LifecycleStage) {
        lock.lock()
        defer { lock.unlock() }

        guard var stageInfo = stages[stage] else {
            logger.warning("Attempted to complete non-existent stage: \(stage)")
            return
        }

        stageInfo.progress = 1.0
        stageInfo.endTime = Date()
        stages[stage] = stageInfo

        // Store duration for future estimates
        let duration = stageInfo.duration
        storeStageDuration(stage, duration: duration)

        logger.debug("Completed stage: \(stage) in \(String(format: "%.2f", duration))s")
    }

    /// Fail a stage
    public func failStage(_ stage: LifecycleStage, error: Error) {
        lock.lock()
        defer { lock.unlock() }

        guard var stageInfo = stages[stage] else {
            logger.warning("Attempted to fail non-existent stage: \(stage)")
            return
        }

        stageInfo.error = error
        stageInfo.endTime = Date()
        stages[stage] = stageInfo

        logger.warning("Failed stage: \(stage) - \(error.localizedDescription)")
    }

    /// Get all stages
    public func getAllStages() -> [LifecycleStage: ProgressStage] {
        lock.lock()
        defer { lock.unlock() }

        return stages
    }

    /// Get a specific stage
    public func getStage(_ stage: LifecycleStage) -> ProgressStage? {
        lock.lock()
        defer { lock.unlock() }

        return stages[stage]
    }

    /// Reset all stages
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        stages.removeAll()
        logger.debug("Reset all stages")
    }

    /// Get estimated time remaining for a stage
    public func estimateTimeRemaining(for stage: LifecycleStage) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        guard let stageInfo = stages[stage], stageInfo.progress > 0 else {
            return getHistoricalAverage(for: stage)
        }

        // Try to estimate based on current progress
        let elapsed = stageInfo.duration
        if elapsed > 0 && stageInfo.progress > 0 {
            let estimatedTotal = elapsed / stageInfo.progress
            return max(0, estimatedTotal - elapsed)
        }

        // Fall back to historical average
        return getHistoricalAverage(for: stage)
    }

    // MARK: - Private Methods

    private func storeStageDuration(_ stage: LifecycleStage, duration: TimeInterval) {
        if stageDurationHistory[stage] == nil {
            stageDurationHistory[stage] = []
        }

        // Keep last 10 durations for averaging
        stageDurationHistory[stage]?.append(duration)
        if stageDurationHistory[stage]!.count > 10 {
            stageDurationHistory[stage]?.removeFirst()
        }
    }

    private func getHistoricalAverage(for stage: LifecycleStage) -> TimeInterval? {
        guard let history = stageDurationHistory[stage], !history.isEmpty else {
            return nil
        }

        return history.reduce(0, +) / Double(history.count)
    }
}
