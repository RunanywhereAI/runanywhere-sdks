import Alamofire
import Files
import Foundation

/// Download service using Alamofire for HTTP and C++ bridge for orchestration
/// C++ handles: task tracking, progress calculation, retry logic
/// Swift handles: HTTP transport via Alamofire, extraction via SWCompression
public class AlamofireDownloadService: @unchecked Sendable {

    // MARK: - Shared Instance

    /// Shared singleton instance
    public static let shared = AlamofireDownloadService()

    // MARK: - Properties

    let session: Session
    var activeDownloadRequests: [String: DownloadRequest] = [:]
    let logger = SDKLogger(category: "AlamofireDownloadService")

    // MARK: - Services

    /// Extraction service for handling archive extraction
    let extractionService: ModelExtractionServiceProtocol

    // MARK: - Initialization

    public init(
        configuration: DownloadConfiguration = DownloadConfiguration(),
        extractionService: ModelExtractionServiceProtocol = DefaultModelExtractionService()
    ) {
        self.extractionService = extractionService

        // Configure session
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
        sessionConfiguration.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfiguration.httpMaximumConnectionsPerHost = configuration.maxConcurrentDownloads

        // Create custom retry policy
        let retryPolicy = RetryPolicy(
            retryLimit: UInt(configuration.retryCount),
            exponentialBackoffBase: 2,
            exponentialBackoffScale: configuration.retryDelay,
            retryableHTTPMethods: [.get, .post]
        )

        self.session = Session(
            configuration: sessionConfiguration,
            interceptor: Interceptor(adapters: [], retriers: [retryPolicy])
        )
    }

    // MARK: - Download API

    /// Download a model
    /// - Parameter model: The model to download
    /// - Returns: A download task tracking the download
    /// - Throws: An error if download setup fails
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        logger.info("Starting artifact-based download for model \(model.id)", metadata: [
            "artifactType": model.artifactType.displayName,
            "requiresExtraction": model.artifactType.requiresExtraction
        ])

        return try await downloadModelWithArtifactType(model)
    }

    public func cancelDownload(taskId: String) {
        if let downloadRequest = activeDownloadRequests[taskId] {
            downloadRequest.cancel()
            activeDownloadRequests.removeValue(forKey: taskId)

            // Notify C++ bridge
            Task {
                try? await CppBridge.Download.shared.cancelDownload(taskId: taskId)
            }

            CppBridge.Events.emitDownloadCancelled(modelId: taskId)
            logger.info("Cancelled download task: \(taskId)")
        }
    }

    // MARK: - Public Methods

    /// Pause all active downloads
    public func pauseAll() {
        activeDownloadRequests.values.forEach { $0.suspend() }
        Task {
            try? await CppBridge.Download.shared.pauseAll()
        }
        logger.info("Paused all downloads")
    }

    /// Resume all paused downloads
    public func resumeAll() {
        activeDownloadRequests.values.forEach { $0.resume() }
        Task {
            try? await CppBridge.Download.shared.resumeAll()
        }
        logger.info("Resumed all downloads")
    }

    /// Check if service is healthy
    public func isHealthy() -> Bool {
        return true
    }

    // MARK: - Internal Download Methods

    /// Download model using artifact-type-based approach
    func downloadModelWithArtifactType(_ model: ModelInfo) async throws -> DownloadTask {
        // Handle multi-file models (like VLMs with separate main model + mmproj)
        if case .multiFile(var files) = model.artifactType {
            // If files are empty, try to get them from the cache
            // (C++ registry doesn't preserve file descriptors)
            if files.isEmpty, let cachedFiles = RunAnywhere.getMultiFileDescriptors(forModelId: model.id) {
                files = cachedFiles
                logger.info("Retrieved \(files.count) file descriptors from cache for model: \(model.id)")
            }
            return try await downloadMultiFileModel(model, files: files)
        }

        guard let downloadURL = model.downloadURL else {
            let downloadError = SDKError.download(.invalidInput, "Invalid download URL for model: \(model.id)")
            CppBridge.Events.emitDownloadFailed(modelId: model.id, error: downloadError)
            throw downloadError
        }

        // Track download started via C++ event system
        CppBridge.Events.emitDownloadStarted(modelId: model.id, totalBytes: model.downloadSize ?? 0)

        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        // Determine if we need extraction
        // First check artifact type, then infer from URL if not explicitly set
        var requiresExtraction = model.artifactType.requiresExtraction

        // If artifact type doesn't require extraction, check if URL indicates an archive
        // This is a safeguard for models registered without explicit artifact type
        if !requiresExtraction, let archiveType = ArchiveType.from(url: downloadURL) {
            logger.info("URL indicates archive type (\(archiveType.rawValue)) but artifact type doesn't require extraction. Inferring extraction needed.")
            requiresExtraction = true
        }

        // Get destination path from C++ path utilities
        logger.info("Computing download path for model: \(model.id), framework: \(model.framework.rawValue) (\(model.framework.displayName))")
        let destinationFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)
        logger.info("Destination folder: \(destinationFolder.path)")

        // Start tracking in C++ download manager
        let taskId = try await CppBridge.Download.shared.startDownload(
            modelId: model.id,
            url: downloadURL,
            destinationPath: destinationFolder,
            requiresExtraction: requiresExtraction
        ) { progress in
            progressContinuation.yield(progress)
        }

        // Create download task
        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    self.activeDownloadRequests.removeValue(forKey: taskId)
                }

                do {
                    return try await self.executeArtifactDownload(
                        model: model,
                        downloadURL: downloadURL,
                        taskId: taskId,
                        requiresExtraction: requiresExtraction,
                        downloadStartTime: downloadStartTime,
                        destinationFolder: destinationFolder,
                        progressContinuation: progressContinuation
                    )
                } catch {
                    // Notify C++ bridge of failure
                    await CppBridge.Download.shared.markFailed(
                        taskId: taskId,
                        error: SDKError.from(error, category: .download)
                    )
                    progressContinuation.yield(.failed(error, bytesDownloaded: 0, totalBytes: model.downloadSize ?? 0))
                    throw error
                }
            }
        )

        return task
    }

    // MARK: - Multi-File Download

    /// Download a model that consists of multiple separate files (e.g., VLM with main model + mmproj)
    private func downloadMultiFileModel(_ model: ModelInfo, files: [ModelFileDescriptor]) async throws -> DownloadTask {
        guard !files.isEmpty else {
            throw SDKError.download(.invalidInput, "No files specified for multi-file model: \(model.id)")
        }

        logger.info("Starting multi-file download for \(model.id) with \(files.count) files")
        CppBridge.Events.emitDownloadStarted(modelId: model.id, totalBytes: model.downloadSize ?? 0)

        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()
        let destinationFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)
        let taskId = "download-multifile-\(model.id)-\(UUID().uuidString.prefix(8))"

        // Create download task
        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    self.activeDownloadRequests.removeValue(forKey: taskId)
                }

                do {
                    // Download each file sequentially
                    var totalBytesDownloaded: Int64 = 0
                    let fileCount = files.count

                    for (index, fileDescriptor) in files.enumerated() {
                        let fileDestination = destinationFolder.appendingPathComponent(fileDescriptor.filename)
                        logger.info("Downloading file \(index + 1)/\(fileCount): \(fileDescriptor.filename)")

                        // Download this file
                        _ = try await self.performDownload(
                            url: fileDescriptor.url,
                            destination: fileDestination,
                            model: model,
                            taskId: "\(taskId)-\(index)",
                            progressContinuation: progressContinuation,
                            progressOffset: Double(index) / Double(fileCount),
                            progressScale: 1.0 / Double(fileCount)
                        )

                        // Get file size for logging
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileDestination.path),
                           let size = attrs[.size] as? Int64 {
                            totalBytesDownloaded += size
                        }

                        logger.info("Completed file \(index + 1)/\(fileCount): \(fileDescriptor.filename)")
                    }

                    // All files downloaded - mark complete
                    CppBridge.Events.emitDownloadCompleted(
                        modelId: model.id,
                        durationMs: Date().timeIntervalSince(downloadStartTime) * 1000,
                        sizeBytes: totalBytesDownloaded
                    )

                    // Update model registry with local path
                    try await CppBridge.ModelRegistry.shared.updateDownloadStatus(
                        modelId: model.id,
                        localPath: destinationFolder
                    )

                    let totalTime = Date().timeIntervalSince(downloadStartTime)
                    logger.info("Multi-file download complete for \(model.id): \(files.count) files in \(String(format: "%.1f", totalTime))s")

                    progressContinuation.yield(.completed(totalBytes: totalBytesDownloaded))

                    return destinationFolder
                } catch {
                    CppBridge.Events.emitDownloadFailed(modelId: model.id, error: SDKError.from(error, category: .download))
                    progressContinuation.yield(.failed(error, bytesDownloaded: 0, totalBytes: model.downloadSize ?? 0))
                    throw error
                }
            }
        )

        return task
    }

    /// Execute the complete download workflow for artifact-based downloads
    func executeArtifactDownload(
        model: ModelInfo,
        downloadURL: URL,
        taskId: String,
        requiresExtraction: Bool,
        downloadStartTime: Date,
        destinationFolder: URL,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Determine download destination
        let downloadDestination = determineDownloadDestination(
            for: model,
            modelFolderURL: destinationFolder,
            requiresExtraction: requiresExtraction
        )

        // Log download start
        logDownloadStart(model: model, url: downloadURL, destination: downloadDestination, requiresExtraction: requiresExtraction)

        // Perform download (Alamofire HTTP)
        let downloadedURL = try await performDownload(
            url: downloadURL,
            destination: downloadDestination,
            model: model,
            taskId: taskId,
            progressContinuation: progressContinuation
        )

        // Notify C++ that download portion is complete
        await CppBridge.Download.shared.markComplete(taskId: taskId, downloadedPath: downloadedURL)

        // Handle extraction if needed
        let finalModelPath = try await handlePostDownloadProcessing(
            downloadedURL: downloadedURL,
            modelFolderURL: destinationFolder,
            model: model,
            requiresExtraction: requiresExtraction,
            progressContinuation: progressContinuation
        )

        // Update model metadata via C++ registry
        try await updateModelMetadata(model: model, localPath: finalModelPath)

        // Track completion
        trackDownloadCompletion(model: model, finalPath: finalModelPath, startTime: downloadStartTime, progressContinuation: progressContinuation)

        return finalModelPath
    }

    /// Determine the download destination based on extraction requirements
    private func determineDownloadDestination(
        for model: ModelInfo,
        modelFolderURL: URL,
        requiresExtraction: Bool
    ) -> URL {
        if requiresExtraction {
            // Download to temp location for archives
            // Get archive extension - use the one from artifact type or infer from URL
            let archiveExt = getArchiveExtensionFromModelOrURL(model)

            // Note: URL.appendingPathExtension doesn't work well with multi-part extensions like "tar.gz"
            // So we construct the filename with extension directly
            let filename = "\(model.id)_\(UUID().uuidString).\(archiveExt)"
            return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        } else {
            // Download directly to model folder
            return modelFolderURL.appendingPathComponent("\(model.id).\(model.format.rawValue)")
        }
    }

    /// Get archive extension from model's artifact type or infer from download URL
    private func getArchiveExtensionFromModelOrURL(_ model: ModelInfo) -> String {
        // First try to get from artifact type
        if case .archive(let archiveType, _, _) = model.artifactType {
            return archiveType.fileExtension
        }

        // If not an explicit archive type, try to infer from download URL
        if let url = model.downloadURL,
           let archiveType = ArchiveType.from(url: url) {
            return archiveType.fileExtension
        }

        // Default to archive (unknown type)
        return "archive"
    }

    /// Log download start information
    private func logDownloadStart(model: ModelInfo, url: URL, destination: URL, requiresExtraction: Bool) {
        logger.info("Starting download", metadata: [
            "modelId": model.id,
            "url": url.absoluteString,
            "expectedSize": model.downloadSize ?? 0,
            "destination": destination.path,
            "requiresExtraction": requiresExtraction
        ])
    }

    /// Handle post-download processing (extraction if needed)
    private func handlePostDownloadProcessing(
        downloadedURL: URL,
        modelFolderURL: URL,
        model: ModelInfo,
        requiresExtraction: Bool,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        if requiresExtraction {
            let finalPath = try await performExtraction(
                archiveURL: downloadedURL,
                destinationFolder: modelFolderURL,
                model: model,
                progressContinuation: progressContinuation
            )
            // Clean up archive
            try? FileManager.default.removeItem(at: downloadedURL)
            return finalPath
        } else {
            return downloadedURL
        }
    }

    /// Update model metadata via C++ registry
    private func updateModelMetadata(model: ModelInfo, localPath: URL) async throws {
        var updatedModel = model
        updatedModel.localPath = localPath
        try await CppBridge.ModelRegistry.shared.save(updatedModel)
        logger.info("Model metadata saved successfully for: \(model.id)")
    }

    /// Track download completion with analytics
    func trackDownloadCompletion(
        model: ModelInfo,
        finalPath: URL,
        startTime: Date,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) {
        let durationMs = Date().timeIntervalSince(startTime) * 1000
        let fileSize = FileOperationsUtilities.fileSize(at: finalPath) ?? model.downloadSize ?? 0

        CppBridge.Events.emitDownloadCompleted(
            modelId: model.id,
            durationMs: durationMs,
            sizeBytes: fileSize
        )

        // Report completion
        progressContinuation.yield(.completed(totalBytes: model.downloadSize ?? fileSize))

        logger.info("Download completed", metadata: [
            "modelId": model.id,
            "localPath": finalPath.path,
            "fileSize": fileSize
        ])
    }

    // MARK: - Helper Methods

    func mapAlamofireError(_ error: AFError) -> SDKError {
        switch error {
        case .sessionTaskFailed(let underlyingError):
            let message = "Network error during download: \(underlyingError.localizedDescription)"
            return SDKError.download(.networkError, message, underlying: underlyingError)
        case .responseValidationFailed(reason: let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return SDKError.download(.httpError, "HTTP error \(code)")
            default:
                return SDKError.download(.invalidResponse, "Invalid response from server")
            }
        case .createURLRequestFailed, .invalidURL:
            return SDKError.download(.invalidInput, "Invalid URL")
        default:
            return SDKError.download(.unknown, "Unknown download error: \(error.localizedDescription)")
        }
    }
}
