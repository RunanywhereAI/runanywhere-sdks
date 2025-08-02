import Foundation

/// Protocol for performance monitoring
public protocol PerformanceMonitor {
    /// Initialize the performance monitor
    func initialize() async

    /// Start monitoring
    func startMonitoring() async

    /// Stop monitoring
    func stopMonitoring() async

    /// Track a generation event
    func trackGeneration(
        duration: TimeInterval,
        tokenCount: Int,
        executionTarget: ExecutionTarget
    ) async

    /// Get current performance metrics
    func getCurrentMetrics() -> PerformanceMetrics
}
