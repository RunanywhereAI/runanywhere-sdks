import Foundation

/// Extended observer protocol for progress updates
public protocol ModelLifecycleProgressObserver: ModelLifecycleObserver {
    /// Called when model loading/unloading progress is updated
    func modelDidUpdateProgress(_ progress: ModelLifecycleProgress)
}

/// Progress information for lifecycle operations
public struct ModelLifecycleProgress {
    public let currentState: ModelLifecycleState
    public let percentage: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let message: String?

    public init(
        currentState: ModelLifecycleState,
        percentage: Double,
        estimatedTimeRemaining: TimeInterval? = nil,
        message: String? = nil
    ) {
        self.currentState = currentState
        self.percentage = max(0.0, min(100.0, percentage))
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.message = message
    }
}
