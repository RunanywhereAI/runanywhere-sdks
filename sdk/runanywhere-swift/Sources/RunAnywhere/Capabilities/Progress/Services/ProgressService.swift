//
//  ProgressService.swift
//  RunAnywhere SDK
//
//  Main progress tracking service
//

import Foundation
import Combine

/// Main service for tracking progress across multiple stages
public class ProgressService: ProgressTracker {

    // MARK: - Properties

    /// Stage manager for handling stage operations
    private let stageManager: StageManager

    /// Progress aggregator for calculating overall progress
    private let progressAggregator: ProgressAggregator

    /// Thread-safe access to observers
    private var observers: [UUID: WeakObserver] = [:]
    private let observerLock = NSLock()

    /// Progress publisher for Combine support
    private let progressSubject = PassthroughSubject<OverallProgress, Never>()

    /// Logger
    private let logger = SDKLogger(category: "ProgressService")

    // MARK: - Types

    private class WeakObserver {
        weak var observer: ProgressObserver?

        init(observer: ProgressObserver) {
            self.observer = observer
        }
    }

    // MARK: - Initialization

    public init(
        stageManager: StageManager? = nil,
        progressAggregator: ProgressAggregator? = nil
    ) {
        self.stageManager = stageManager ?? StageManager()
        self.progressAggregator = progressAggregator ?? ProgressAggregator()
    }

    // MARK: - ProgressTracker Protocol

    public func startStage(_ stage: LifecycleStage) {
        logger.debug("Starting stage: \(stage)")
        stageManager.startStage(stage)
        notifyProgress()
    }

    public func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String?) {
        logger.debug("Updating stage \(stage): \(Int(progress * 100))%")
        stageManager.updateStageProgress(stage, progress: progress, message: message)
        notifyProgress()
    }

    public func completeStage(_ stage: LifecycleStage) {
        logger.debug("Completing stage: \(stage)")
        stageManager.completeStage(stage)
        notifyProgress()
        notifyStageComplete(stage)
    }

    public func failStage(_ stage: LifecycleStage, error: Error) {
        logger.error("Stage \(stage) failed: \(error.localizedDescription)")
        stageManager.failStage(stage, error: error)
        notifyProgress()
        notifyStageFailure(stage, error: error)
    }

    public func getCurrentProgress() -> OverallProgress {
        let stages = stageManager.getAllStages()
        let aggregated = progressAggregator.aggregate(stages: stages)
        return aggregated.asOverallProgress
    }

    public func addObserver(_ observer: ProgressObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        let id = UUID()
        observers[id] = WeakObserver(observer: observer)

        // Cleanup dead references
        cleanupObservers()
    }

    public func removeObserver(_ observer: ProgressObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        observers = observers.filter { $0.value.observer !== observer }
    }

    // MARK: - Public Extensions

    /// Get progress as a Combine publisher
    public var progressPublisher: AnyPublisher<OverallProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    /// Reset all progress
    public func reset() {
        logger.debug("Resetting all progress")
        stageManager.reset()
        notifyProgress()
    }

    /// Get detailed aggregated progress
    public func getAggregatedProgress() -> AggregatedProgress {
        let stages = stageManager.getAllStages()
        return progressAggregator.aggregate(stages: stages)
    }

    /// Get stage information
    public func getStageInfo(for stage: LifecycleStage) -> ProgressStage? {
        return stageManager.getStage(stage)
    }

    // MARK: - Private Methods

    private func notifyProgress() {
        let progress = getCurrentProgress()
        progressSubject.send(progress)

        observerLock.lock()
        let activeObservers = observers.compactMap { $0.value.observer }
        observerLock.unlock()

        for observer in activeObservers {
            observer.progressDidUpdate(progress)
        }
    }

    private func notifyStageComplete(_ stage: LifecycleStage) {
        observerLock.lock()
        let activeObservers = observers.compactMap { $0.value.observer }
        observerLock.unlock()

        for observer in activeObservers {
            observer.stageDidComplete(stage)
        }
    }

    private func notifyStageFailure(_ stage: LifecycleStage, error: Error) {
        observerLock.lock()
        let activeObservers = observers.compactMap { $0.value.observer }
        observerLock.unlock()

        for observer in activeObservers {
            observer.stageDidFail(stage, error: error)
        }
    }

    private func cleanupObservers() {
        observers = observers.filter { $0.value.observer != nil }
    }
}
