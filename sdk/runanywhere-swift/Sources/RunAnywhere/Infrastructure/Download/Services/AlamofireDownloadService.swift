import Alamofire
import Files
import Foundation

/// Simplified download service using Alamofire
public class AlamofireDownloadService: DownloadService, @unchecked Sendable {

    // MARK: - Properties

    let session: Session
    var activeDownloadRequests: [String: DownloadRequest] = [:]
    let logger = SDKLogger(category: "AlamofireDownloadService")

    // MARK: - Services

    /// Extraction service for handling archive extraction
    let extractionService: ModelExtractionServiceProtocol

    /// Helper for handling download progress
    let progressHandler: DownloadProgressHandler

    // MARK: - Custom Download Strategies

    /// Storage for custom download strategies provided by host app
    var customStrategies: [DownloadStrategy] = []

    // MARK: - Initialization

    public init(
        configuration: DownloadConfiguration = DownloadConfiguration(),
        extractionService: ModelExtractionServiceProtocol = DefaultModelExtractionService()
    ) {
        self.extractionService = extractionService
        self.progressHandler = DownloadProgressHandler()

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

    // MARK: - DownloadService Protocol

    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        // First, check if a custom strategy should handle this model
        if case .custom(let strategyId) = model.artifactType {
            logger.info("Model \(model.id) requires custom strategy: \(strategyId)")
            if let strategy = await MainActor.run(body: { findCustomStrategy(for: model) }) {
                return try await downloadModelWithCustomStrategy(model, strategy: strategy)
            }
        }

        // Check if any registered custom strategy can handle this model
        for strategy in customStrategies where strategy.canHandle(model: model) {
            logger.info("Using custom strategy \(type(of: strategy)) for model \(model.id)")
            return try await downloadModelWithCustomStrategy(model, strategy: strategy)
        }

        // Use artifact-type-based download handling
        logger.info("Using artifact-based download for model \(model.id)", metadata: [
            "artifactType": model.artifactType.displayName,
            "requiresExtraction": model.artifactType.requiresExtraction
        ])

        return try await downloadModelWithArtifactType(model)
    }

    public func cancelDownload(taskId: String) {
        if let downloadRequest = activeDownloadRequests[taskId] {
            downloadRequest.cancel()
            activeDownloadRequests.removeValue(forKey: taskId)

            EventPublisher.shared.track(ModelEvent.downloadCancelled(modelId: taskId))
            logger.info("Cancelled download task: \(taskId)")
        }
    }

    // MARK: - Public Methods

    /// Pause all active downloads
    public func pauseAll() {
        activeDownloadRequests.values.forEach { $0.suspend() }
        logger.info("Paused all downloads")
    }

    /// Resume all paused downloads
    public func resumeAll() {
        activeDownloadRequests.values.forEach { $0.resume() }
        logger.info("Resumed all downloads")
    }

    /// Check if service is healthy
    public func isHealthy() -> Bool {
        return true
    }

    // MARK: - Internal Download Methods

    /// Download model using artifact-type-based approach
    func downloadModelWithArtifactType(_ model: ModelInfo) async throws -> DownloadTask {
        guard let downloadURL = model.downloadURL else {
            EventPublisher.shared.track(ModelEvent.downloadFailed(modelId: model.id, error: "Invalid download URL"))
            throw SDKError.download(.invalidInput, "Invalid download URL for model: \(model.id)")
        }

        // Track download started
        EventPublisher.shared.track(ModelEvent.downloadStarted(modelId: model.id))

        let taskId = UUID().uuidString
        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        // Determine if we need extraction
        let requiresExtraction = model.artifactType.requiresExtraction

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
                        progressContinuation: progressContinuation
                    )
                } catch {
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
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Get destination folder (framework is required - 1:1 mapping)
        let framework = model.framework
        let fileManager = ServiceContainer.shared.fileManager
        let modelFolder = try fileManager.getModelFolder(for: model.id, framework: framework)
        let modelFolderURL = URL(fileURLWithPath: modelFolder.path)

        // Determine download destination
        let downloadDestination = determineDownloadDestination(
            for: model,
            modelFolderURL: modelFolderURL,
            requiresExtraction: requiresExtraction
        )

        // Log download start
        logDownloadStart(model: model, url: downloadURL, destination: downloadDestination, requiresExtraction: requiresExtraction)

        // Perform download
        let downloadedURL = try await performDownload(
            url: downloadURL,
            destination: downloadDestination,
            model: model,
            taskId: taskId,
            progressContinuation: progressContinuation
        )

        // Handle extraction if needed
        let finalModelPath = try await handlePostDownloadProcessing(
            downloadedURL: downloadedURL,
            modelFolderURL: modelFolderURL,
            model: model,
            requiresExtraction: requiresExtraction,
            progressContinuation: progressContinuation
        )

        // Update and save model
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
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("\(model.id)_\(UUID().uuidString)")
                .appendingPathExtension(getArchiveExtension(for: model.artifactType))
        } else {
            // Download directly to model folder
            return modelFolderURL.appendingPathComponent("\(model.id).\(model.format.rawValue)")
        }
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

    /// Update model metadata in registry and persistent storage
    private func updateModelMetadata(model: ModelInfo, localPath: URL) async throws {
        var updatedModel = model
        updatedModel.localPath = localPath
        ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

        // Save metadata persistently
        Task {
            do {
                let modelInfoService = await ServiceContainer.shared.modelInfoService
                try await modelInfoService.saveModel(updatedModel)
                self.logger.info("Model metadata saved successfully for: \(model.id)")
            } catch {
                self.logger.error("Failed to save model metadata for \(model.id): \(error)")
            }
        }
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

        EventPublisher.shared.track(ModelEvent.downloadCompleted(
            modelId: model.id,
            durationMs: durationMs,
            sizeBytes: fileSize
        ))

        // Report completion
        progressContinuation.yield(.completed(totalBytes: model.downloadSize ?? fileSize))

        logger.info("Download completed", metadata: [
            "modelId": model.id,
            "localPath": finalPath.path,
            "fileSize": fileSize
        ])
    }

    /// Get archive extension from artifact type
    func getArchiveExtension(for artifactType: ModelArtifactType) -> String {
        guard case .archive(let archiveType, _, _) = artifactType else {
            return "archive"
        }
        return archiveType.fileExtension
    }

    // MARK: - Helper Methods

    func calculateDownloadSpeed(progress: Progress) -> String {
        return progressHandler.calculateSpeed(progress: progress)
    }

    func mapAlamofireError(_ error: AFError) -> Error {
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
