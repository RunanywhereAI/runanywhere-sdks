//
//  ProgressTracker.swift
//  RunAnywhere SDK
//
//  Protocol for tracking operation progress
//

import Foundation

/// Protocol for tracking progress across multiple stages
public protocol ProgressTracker {
    /// Start a new stage
    /// - Parameter stage: The lifecycle stage
    func startStage(_ stage: LifecycleStage)

    /// Update stage progress
    /// - Parameters:
    ///   - stage: The lifecycle stage
    ///   - progress: Progress value (0.0 to 1.0)
    ///   - message: Optional status message
    func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String?)

    /// Complete a stage
    /// - Parameter stage: The lifecycle stage
    func completeStage(_ stage: LifecycleStage)

    /// Fail a stage
    /// - Parameters:
    ///   - stage: The lifecycle stage
    ///   - error: The error that occurred
    func failStage(_ stage: LifecycleStage, error: Error)

    /// Get current overall progress
    /// - Returns: Current progress information
    func getCurrentProgress() -> OverallProgress

    /// Add a progress observer
    /// - Parameter observer: The observer to add
    func addObserver(_ observer: ProgressObserver)

    /// Remove a progress observer
    /// - Parameter observer: The observer to remove
    func removeObserver(_ observer: ProgressObserver)
}
