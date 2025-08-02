import Foundation

/// Manages download queue with priority and concurrency control
public actor DownloadQueue {

    // MARK: - Properties

    private var queue: [QueuedDownload] = []
    private var activeDownloads: [String: Task<Void, Error>] = [:]
    private var maxConcurrent: Int
    private var isPaused = false
    private let logger = SDKLogger(category: "DownloadQueue")

    // MARK: - Types

    private struct QueuedDownload {
        let taskId: String
        let priority: DownloadPriority
        let handler: () async throws -> Void
    }

    public enum DownloadPriority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3

        public static func < (lhs: DownloadPriority, rhs: DownloadPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Initialization

    public init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public Methods

    /// Enqueue a download
    public func enqueue(
        taskId: String,
        priority: DownloadPriority = .normal,
        handler: @escaping () async throws -> Void
    ) async {
        logger.debug("Enqueuing download \(taskId) with priority \(priority)")

        let download = QueuedDownload(taskId: taskId, priority: priority, handler: handler)
        queue.append(download)
        queue.sort { $0.priority > $1.priority }

        await processQueue()
    }

    /// Cancel a download
    public func cancel(taskId: String) async {
        logger.debug("Cancelling download \(taskId)")

        // Remove from queue
        queue.removeAll { $0.taskId == taskId }

        // Cancel active download
        if let task = activeDownloads[taskId] {
            task.cancel()
            activeDownloads.removeValue(forKey: taskId)
        }

        await processQueue()
    }

    /// Set maximum concurrent downloads
    public func setMaxConcurrent(_ max: Int) async {
        logger.info("Setting max concurrent downloads to \(max)")
        maxConcurrent = max
        await processQueue()
    }

    /// Pause all downloads
    public func pauseAll() async {
        logger.info("Pausing download queue")
        isPaused = true
    }

    /// Resume all downloads
    public func resumeAll() async {
        logger.info("Resuming download queue")
        isPaused = false
        await processQueue()
    }

    /// Get queued count
    public var queuedCount: Int {
        get async { queue.count }
    }

    /// Get active count
    public var activeCount: Int {
        get async { activeDownloads.count }
    }

    // MARK: - Private Methods

    private func processQueue() async {
        guard !isPaused else { return }

        // Start downloads up to max concurrent
        while activeDownloads.count < maxConcurrent && !queue.isEmpty {
            let download = queue.removeFirst()

            let task = Task {
                defer {
                    Task {
                        await self.downloadCompleted(taskId: download.taskId)
                    }
                }

                do {
                    try await download.handler()
                } catch {
                    self.logger.error("Download \(download.taskId) failed: \(error)")
                    throw error
                }
            }

            activeDownloads[download.taskId] = task
        }
    }

    private func downloadCompleted(taskId: String) async {
        activeDownloads.removeValue(forKey: taskId)
        await processQueue()
    }
}
