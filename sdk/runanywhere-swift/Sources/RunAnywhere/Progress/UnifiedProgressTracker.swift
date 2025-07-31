import Foundation
import Combine

/// Implementation of unified progress tracking
public class UnifiedProgressTracker: ProgressTracker {
    // MARK: - Properties
    
    private var stages: [LifecycleStage: StageInfo] = [:]
    private let stageLock = NSLock()
    
    private var observers: [UUID: WeakObserver] = [:]
    private let observerLock = NSLock()
    
    private let progressSubject = PassthroughSubject<OverallProgress, Never>()
    
    // Stage duration history for time estimation
    private var stageDurationHistory: [LifecycleStage: [TimeInterval]] = [:]
    
    // MARK: - Types
    
    private struct StageInfo {
        let stage: LifecycleStage
        var startTime: Date
        var endTime: Date?
        var progress: Double = 0
        var message: String = ""
        var subStages: [String: Double] = [:]
        var error: Error?
    }
    
    private class WeakObserver {
        weak var observer: ProgressObserver?
        
        init(observer: ProgressObserver) {
            self.observer = observer
        }
    }
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - ProgressTracker Protocol
    
    public func startStage(_ stage: LifecycleStage) {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        stages[stage] = StageInfo(
            stage: stage,
            startTime: Date(),
            message: stage.defaultMessage
        )
        
        notifyProgress()
    }
    
    public func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String?) {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        guard var stageInfo = stages[stage] else { return }
        
        stageInfo.progress = min(1.0, max(0.0, progress))
        if let message = message {
            stageInfo.message = message
        }
        
        stages[stage] = stageInfo
        notifyProgress()
    }
    
    public func completeStage(_ stage: LifecycleStage) {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        guard var stageInfo = stages[stage] else { return }
        
        stageInfo.progress = 1.0
        stageInfo.endTime = Date()
        stages[stage] = stageInfo
        
        // Store duration for future estimates
        let duration = stageInfo.endTime!.timeIntervalSince(stageInfo.startTime)
        storeStageDuration(stage, duration: duration)
        
        notifyProgress()
        notifyStageComplete(stage)
    }
    
    public func failStage(_ stage: LifecycleStage, error: Error) {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        guard var stageInfo = stages[stage] else { return }
        
        stageInfo.error = error
        stageInfo.endTime = Date()
        stages[stage] = stageInfo
        
        notifyProgress()
        notifyStageFailure(stage, error: error)
    }
    
    public func getCurrentProgress() -> OverallProgress {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        let stageWeights: [LifecycleStage: Double] = [
            .discovery: 0.05,
            .download: 0.25,
            .extraction: 0.10,
            .validation: 0.05,
            .initialization: 0.15,
            .loading: 0.30,
            .ready: 0.10
        ]
        
        var totalProgress = 0.0
        var totalWeight = 0.0
        var currentStage: LifecycleStage?
        var currentStageProgress = 0.0
        var currentMessage = ""
        var estimatedTimeRemaining: TimeInterval?
        
        // Calculate weighted progress
        for (stage, info) in stages {
            let weight = stageWeights[stage] ?? 0.1
            totalProgress += info.progress * weight
            totalWeight += weight
            
            // Find current active stage
            if info.endTime == nil && info.error == nil && currentStage == nil {
                currentStage = stage
                currentStageProgress = info.progress
                currentMessage = info.message
                estimatedTimeRemaining = estimateTimeRemaining(for: stage, progress: info.progress)
            }
        }
        
        // Normalize progress
        let overallProgress = totalWeight > 0 ? totalProgress / totalWeight : 0
        
        return OverallProgress(
            percentage: overallProgress,
            currentStage: currentStage,
            stageProgress: currentStageProgress,
            message: currentMessage,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
    }
    
    public func addObserver(_ observer: ProgressObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }
        
        let id = UUID()
        observers[id] = WeakObserver(observer: observer)
    }
    
    public func removeObserver(_ observer: ProgressObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }
        
        observers = observers.filter { $0.value.observer !== observer }
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
    
    private func estimateTimeRemaining(for stage: LifecycleStage, progress: Double) -> TimeInterval? {
        guard progress > 0 else { return nil }
        
        // Try to estimate based on current progress
        if let stageInfo = stages[stage] {
            let elapsed = Date().timeIntervalSince(stageInfo.startTime)
            if elapsed > 0 && progress > 0 {
                let estimatedTotal = elapsed / progress
                return max(0, estimatedTotal - elapsed)
            }
        }
        
        // Fall back to historical average
        if let history = stageDurationHistory[stage], !history.isEmpty {
            let avgDuration = history.reduce(0, +) / Double(history.count)
            return avgDuration * (1.0 - progress)
        }
        
        return nil
    }
}

// MARK: - Public Extensions

public extension UnifiedProgressTracker {
    /// Get progress as a Combine publisher
    var progressPublisher: AnyPublisher<OverallProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    /// Reset all progress
    func reset() {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        stages.removeAll()
        notifyProgress()
    }
    
    /// Get detailed stage information
    func getStageInfo(for stage: LifecycleStage) -> (progress: Double, message: String, duration: TimeInterval?)? {
        stageLock.lock()
        defer { stageLock.unlock() }
        
        guard let info = stages[stage] else { return nil }
        
        let duration: TimeInterval?
        if let endTime = info.endTime {
            duration = endTime.timeIntervalSince(info.startTime)
        } else {
            duration = Date().timeIntervalSince(info.startTime)
        }
        
        return (info.progress, info.message, duration)
    }
}