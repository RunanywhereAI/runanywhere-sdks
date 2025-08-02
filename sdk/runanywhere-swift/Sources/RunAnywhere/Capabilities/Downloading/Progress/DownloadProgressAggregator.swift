import Foundation
import Combine

/// Aggregates progress from multiple download sources
public class DownloadProgressAggregator {

    // MARK: - Properties

    private var progressStreams: [String: AsyncStream<DownloadProgress>] = [:]
    private let aggregatedProgressSubject = PassthroughSubject<AggregatedProgress, Never>()
    private let logger = SDKLogger(category: "ProgressAggregator")

    public var aggregatedProgress: AnyPublisher<AggregatedProgress, Never> {
        aggregatedProgressSubject.eraseToAnyPublisher()
    }

    // MARK: - Types

    public struct AggregatedProgress {
        public let totalTasks: Int
        public let completedTasks: Int
        public let failedTasks: Int
        public let totalBytesDownloaded: Int64
        public let totalBytesExpected: Int64
        public let overallPercentage: Double
        public let tasksProgress: [String: DownloadProgress]

        public var isComplete: Bool {
            completedTasks + failedTasks == totalTasks
        }
    }

    // MARK: - Public Methods

    /// Add a progress stream to aggregate
    public func addProgressStream(taskId: String, stream: AsyncStream<DownloadProgress>) {
        progressStreams[taskId] = stream

        // Monitor the stream
        Task {
            for await progress in stream {
                await updateProgress(taskId: taskId, progress: progress)
            }
            // Stream completed
            await removeStream(taskId: taskId)
        }
    }

    /// Remove a progress stream
    public func removeProgressStream(taskId: String) {
        progressStreams.removeValue(forKey: taskId)
    }

    /// Get current aggregated progress
    public func getCurrentProgress() async -> AggregatedProgress {
        var totalBytesDownloaded: Int64 = 0
        var totalBytesExpected: Int64 = 0
        var completedTasks = 0
        var failedTasks = 0
        var tasksProgress: [String: DownloadProgress] = [:]

        // This is a simplified implementation
        // In a real implementation, we'd track actual progress values

        let totalTasks = progressStreams.count
        let overallPercentage = totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0

        return AggregatedProgress(
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            failedTasks: failedTasks,
            totalBytesDownloaded: totalBytesDownloaded,
            totalBytesExpected: totalBytesExpected,
            overallPercentage: overallPercentage,
            tasksProgress: tasksProgress
        )
    }

    // MARK: - Private Methods

    private func updateProgress(taskId: String, progress: DownloadProgress) async {
        // Update internal state and publish aggregated progress
        let aggregated = await getCurrentProgress()
        aggregatedProgressSubject.send(aggregated)
    }

    private func removeStream(taskId: String) async {
        progressStreams.removeValue(forKey: taskId)
        let aggregated = await getCurrentProgress()
        aggregatedProgressSubject.send(aggregated)
    }
}
