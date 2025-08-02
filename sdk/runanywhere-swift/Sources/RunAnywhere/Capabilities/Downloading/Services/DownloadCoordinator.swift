import Foundation

/// Coordinates download operations between queue and session
public class DownloadCoordinator {

    // MARK: - Properties

    private let queue: DownloadQueue
    private let session: DownloadSession
    private let progressTracker: DownloadProgressTracker
    private let retryStrategy: RetryStrategy
    private let logger = SDKLogger(category: "DownloadCoordinator")

    // MARK: - Initialization

    public init(
        queue: DownloadQueue,
        session: DownloadSession,
        progressTracker: DownloadProgressTracker,
        retryStrategy: RetryStrategy? = nil
    ) {
        self.queue = queue
        self.session = session
        self.progressTracker = progressTracker
        self.retryStrategy = retryStrategy ?? RetryStrategy()
    }

    // MARK: - Public Methods

    /// Coordinate model download
    public func download(
        model: ModelInfo,
        taskId: String,
        progressHandler: @escaping (DownloadProgress) async -> Void
    ) async throws -> URL {
        guard let downloadURL = model.downloadURL else {
            throw DownloadError.invalidURL
        }

        logger.info("Coordinating download for model \(model.id) from \(downloadURL)")

        // Start tracking
        await progressTracker.startTracking(taskId: taskId, totalBytes: model.downloadSize ?? 0)

        do {
            // Enqueue download with retry logic
            let url = try await retryStrategy.executeWithRetry {
                try await self.performDownload(
                    url: downloadURL,
                    model: model,
                    taskId: taskId,
                    progressHandler: progressHandler
                )
            }

            // Mark as completed
            await progressTracker.markCompleted(taskId: taskId)

            // Handle archive extraction if needed
            if needsExtraction(url) {
                await progressHandler(DownloadProgress(
                    bytesDownloaded: model.downloadSize ?? 0,
                    totalBytes: model.downloadSize ?? 0,
                    state: .extracting
                ))

                return try await extractArchive(url)
            }

            return url

        } catch {
            await progressTracker.markFailed(taskId: taskId, error: error)
            throw error
        }
    }

    // MARK: - Private Methods

    private func performDownload(
        url: URL,
        model: ModelInfo,
        taskId: String,
        progressHandler: @escaping (DownloadProgress) async -> Void
    ) async throws -> URL {
        // Check if resumable download is possible
        if let partialData = await checkForPartialDownload(model: model) {
            logger.debug("Resuming partial download for model \(model.id)")
            // Handle resume logic here
        }

        // Download data
        let data: Data
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            data = try await session.downloadWithProgress(from: url) { downloaded, total in
                Task {
                    await self.progressTracker.updateProgress(
                        taskId: taskId,
                        bytesDownloaded: downloaded,
                        totalBytes: total
                    )

                    let progress = await self.progressTracker.getProgress(taskId: taskId)
                    await progressHandler(progress)
                }
            }
        } else {
            // Fallback for older versions
            let tempURL = try await session.downloadWithDataTask(from: url) { downloaded, total in
                Task {
                    await self.progressTracker.updateProgress(
                        taskId: taskId,
                        bytesDownloaded: downloaded,
                        totalBytes: total
                    )

                    let progress = await self.progressTracker.getProgress(taskId: taskId)
                    await progressHandler(progress)
                }
            }
            data = try Data(contentsOf: tempURL)
        }

        // Store the downloaded file
        return try await storeModel(data, for: model)
    }

    private func storeModel(_ data: Data, for model: ModelInfo) async throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Create models directory if needed
        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)

        // Generate filename
        let filename = model.downloadURL?.lastPathComponent ?? "\(model.id).model"
        let fileURL = modelsURL.appendingPathComponent(filename)

        // Write data
        try data.write(to: fileURL)

        logger.info("Model stored at: \(fileURL.path)")

        return fileURL
    }

    private func checkForPartialDownload(model: ModelInfo) async -> Data? {
        // Check for partial download files
        // This is a placeholder - implement actual resume logic
        return nil
    }

    private func needsExtraction(_ url: URL) -> Bool {
        let archiveExtensions = ["zip", "gz", "tgz", "tar", "bz2", "tbz2", "xz", "txz"]
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractArchive(_ archive: URL) async throws -> URL {
        // Delegate to archive extractors
        let extractor = ArchiveExtractorFactory.createExtractor(for: archive)
        return try await extractor.extract(archive: archive)
    }
}
