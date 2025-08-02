import Foundation

/// Tracks download progress for multiple tasks
public actor DownloadProgressTracker {

    // MARK: - Properties

    private var tasks: [String: TaskProgress] = [:]
    private let logger = SDKLogger(category: "ProgressTracker")

    public private(set) var completedCount = 0
    public private(set) var failedCount = 0
    public private(set) var totalBytesDownloaded: Int64 = 0

    // MARK: - Types

    private struct TaskProgress {
        var bytesDownloaded: Int64
        var totalBytes: Int64
        var startTime: Date
        var state: DownloadState
        var speed: Double? // Bytes per second

        var estimatedTimeRemaining: TimeInterval? {
            guard let speed = speed, speed > 0, totalBytes > bytesDownloaded else {
                return nil
            }
            let remainingBytes = totalBytes - bytesDownloaded
            return TimeInterval(Double(remainingBytes) / speed)
        }
    }

    // MARK: - Public Methods

    /// Start tracking a download
    public func startTracking(taskId: String, totalBytes: Int64) {
        logger.debug("Starting progress tracking for task \(taskId)")

        tasks[taskId] = TaskProgress(
            bytesDownloaded: 0,
            totalBytes: totalBytes,
            startTime: Date(),
            state: .downloading,
            speed: nil
        )
    }

    /// Update download progress
    public func updateProgress(taskId: String, bytesDownloaded: Int64, totalBytes: Int64) {
        guard var progress = tasks[taskId] else { return }

        let previousBytes = progress.bytesDownloaded
        progress.bytesDownloaded = bytesDownloaded
        progress.totalBytes = totalBytes

        // Calculate download speed
        let elapsed = Date().timeIntervalSince(progress.startTime)
        if elapsed > 0 {
            progress.speed = Double(bytesDownloaded) / elapsed
        }

        // Update total bytes downloaded
        totalBytesDownloaded += (bytesDownloaded - previousBytes)

        tasks[taskId] = progress
    }

    /// Mark download as completed
    public func markCompleted(taskId: String) {
        guard var progress = tasks[taskId] else { return }

        progress.state = .completed
        tasks[taskId] = progress
        completedCount += 1

        logger.info("Task \(taskId) completed")
    }

    /// Mark download as failed
    public func markFailed(taskId: String, error: Error) {
        guard var progress = tasks[taskId] else { return }

        progress.state = .failed(error)
        tasks[taskId] = progress
        failedCount += 1

        logger.error("Task \(taskId) failed: \(error)")
    }

    /// Get current progress for a task
    public func getProgress(taskId: String) -> DownloadProgress {
        guard let progress = tasks[taskId] else {
            return DownloadProgress(
                bytesDownloaded: 0,
                totalBytes: 0,
                state: .pending
            )
        }

        return DownloadProgress(
            bytesDownloaded: progress.bytesDownloaded,
            totalBytes: progress.totalBytes,
            state: progress.state,
            estimatedTimeRemaining: progress.estimatedTimeRemaining
        )
    }

    /// Get all active downloads
    public func getActiveDownloads() -> [String: DownloadProgress] {
        var activeDownloads: [String: DownloadProgress] = [:]

        for (taskId, progress) in tasks {
            if case .downloading = progress.state {
                activeDownloads[taskId] = DownloadProgress(
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytes: progress.totalBytes,
                    state: progress.state,
                    estimatedTimeRemaining: progress.estimatedTimeRemaining
                )
            }
        }

        return activeDownloads
    }

    /// Clear completed tasks
    public func clearCompleted() {
        tasks = tasks.filter { _, progress in
            if case .completed = progress.state {
                return false
            }
            return true
        }
    }
}
