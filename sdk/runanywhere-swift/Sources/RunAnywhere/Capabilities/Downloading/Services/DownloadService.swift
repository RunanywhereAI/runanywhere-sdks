import Foundation

/// Main download service orchestrating all download operations
@MainActor
public class DownloadService: DownloadManager {

    // MARK: - Properties

    private let downloadQueue: DownloadQueue
    private let downloadSession: DownloadSession
    private let downloadCoordinator: DownloadCoordinator
    private let progressTracker: DownloadProgressTracker
    private let modelStorage: ModelStorageManager
    private let checksumValidator: ChecksumValidator
    private let logger = SDKLogger(category: "DownloadService")

    private var activeTasks: [String: DownloadTask] = [:]
    private var configuration: DownloadConfiguration

    // MARK: - Initialization

    public init(
        configuration: DownloadConfiguration = DownloadConfiguration(),
        modelStorage: ModelStorageManager? = nil
    ) {
        self.configuration = configuration
        self.modelStorage = modelStorage ?? ServiceContainer.shared.modelStorageManager

        self.downloadQueue = DownloadQueue(maxConcurrent: configuration.maxConcurrentDownloads)
        self.downloadSession = DownloadSession(configuration: configuration)
        self.progressTracker = DownloadProgressTracker()
        self.checksumValidator = ChecksumValidator()
        self.downloadCoordinator = DownloadCoordinator(
            queue: downloadQueue,
            session: downloadSession,
            progressTracker: progressTracker
        )
    }

    // MARK: - DownloadManager Protocol

    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        let taskId = UUID().uuidString
        logger.info("Starting download for model: \(model.id), task: \(taskId)")

        // Create progress stream
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        // Create download task
        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    Task { @MainActor in
                        self.activeTasks.removeValue(forKey: taskId)
                    }
                }

                do {
                    // Check available space
                    if let requiredSpace = model.downloadSize {
                        let availableSpace = modelStorage.getAvailableSpace()
                        if availableSpace < requiredSpace {
                            throw DownloadError.insufficientSpace
                        }
                    }

                    // Perform download
                    let url = try await downloadCoordinator.download(
                        model: model,
                        taskId: taskId,
                        progressHandler: { progress in
                            progressContinuation.yield(progress)
                        }
                    )

                    // Validate checksum if provided
                    if configuration.verifyChecksum, let expectedChecksum = model.checksum {
                        let isValid = try await checksumValidator.validate(url, expected: expectedChecksum)
                        if !isValid {
                            try? FileManager.default.removeItem(at: url)
                            throw DownloadError.checksumMismatch
                        }
                    }

                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        state: .completed
                    ))

                    logger.info("Download completed for model: \(model.id)")
                    return url

                } catch {
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        state: .failed(error)
                    ))
                    logger.error("Download failed for model \(model.id): \(error)")
                    throw error
                }
            }
        )

        // Store task
        activeTasks[taskId] = task

        return task
    }

    public func cancelDownload(taskId: String) {
        logger.info("Cancelling download task: \(taskId)")

        if let task = activeTasks[taskId] {
            task.result.cancel()
            activeTasks.removeValue(forKey: taskId)
            downloadQueue.cancel(taskId: taskId)
        }
    }

    public func activeDownloads() -> [DownloadTask] {
        return Array(activeTasks.values)
    }

    // MARK: - Public Methods

    /// Configure the download service
    public func configure(_ configuration: DownloadConfiguration) {
        self.configuration = configuration
        downloadQueue.setMaxConcurrent(configuration.maxConcurrentDownloads)
        downloadSession.updateConfiguration(configuration)
    }

    /// Pause all downloads
    public func pauseAll() {
        logger.info("Pausing all downloads")
        downloadQueue.pauseAll()
    }

    /// Resume all downloads
    public func resumeAll() {
        logger.info("Resuming all downloads")
        downloadQueue.resumeAll()
    }

    /// Get download statistics
    public func getStatistics() -> DownloadStatistics {
        return DownloadStatistics(
            activeDownloads: activeTasks.count,
            queuedDownloads: downloadQueue.queuedCount,
            completedDownloads: progressTracker.completedCount,
            failedDownloads: progressTracker.failedCount,
            totalBytesDownloaded: progressTracker.totalBytesDownloaded
        )
    }
}

// MARK: - Supporting Types

/// Download statistics
public struct DownloadStatistics {
    public let activeDownloads: Int
    public let queuedDownloads: Int
    public let completedDownloads: Int
    public let failedDownloads: Int
    public let totalBytesDownloaded: Int64
}
