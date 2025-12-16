import Alamofire
import Files
import Foundation
import Pulse

/// Simplified download service using Alamofire
public class AlamofireDownloadService: DownloadService, @unchecked Sendable {

    // MARK: - Properties

    private let session: Session
    private var activeDownloadRequests: [String: DownloadRequest] = [:]
    private let logger = SDKLogger(category: "AlamofireDownloadService")

    // MARK: - Services

    /// Extraction service for handling archive extraction
    private let extractionService: ModelExtractionServiceProtocol

    /// Helper for managing download tasks
    private let taskManager: DownloadTaskManager

    /// Helper for handling download progress
    private let progressHandler: DownloadProgressHandler

    // MARK: - Custom Download Strategies

    /// Storage for custom download strategies provided by host app
    private var customStrategies: [DownloadStrategy] = []

    // MARK: - Initialization

    public init(
        configuration: DownloadConfiguration = DownloadConfiguration(),
        extractionService: ModelExtractionServiceProtocol = DefaultModelExtractionService()
    ) {
        self.extractionService = extractionService
        self.taskManager = DownloadTaskManager()
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

        // Auto-discover and register download strategies from adapters
        autoRegisterStrategies()
    }

    // MARK: - DownloadService Protocol

    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        // First, check if a custom strategy should handle this model
        // Custom strategies take priority for backwards compatibility
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

    /// Download model using artifact-type-based approach
    private func downloadModelWithArtifactType(_ model: ModelInfo) async throws -> DownloadTask {
        guard let downloadURL = model.downloadURL else {
            EventPublisher.shared.track(ModelEvent.downloadFailed(modelId: model.id, error: "Invalid download URL"))
            throw DownloadError.invalidURL
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
    private func executeArtifactDownload(
        model: ModelInfo,
        downloadURL: URL,
        taskId: String,
        requiresExtraction: Bool,
        downloadStartTime: Date,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Get destination folder (framework is required)
        guard let framework = model.preferredFramework ?? model.compatibleFrameworks.first else {
            logger.error("Model has no associated framework: \(model.id)")
            throw DownloadError.invalidURL
        }
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
    private func trackDownloadCompletion(
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

    /// Find a custom strategy for the model
    /// Checks both manually registered strategies and ModuleRegistry strategies
    @MainActor
    private func findCustomStrategy(for model: ModelInfo) -> DownloadStrategy? {
        // First check manually registered custom strategies (host app priority)
        for strategy in customStrategies where strategy.canHandle(model: model) {
            return strategy
        }

        // Then check ModuleRegistry for module-provided strategies
        if let strategy = ModuleRegistry.shared.downloadStrategy(for: model) {
            return strategy
        }

        return nil
    }

    /// Get archive extension from artifact type
    private func getArchiveExtension(for artifactType: ModelArtifactType) -> String {
        guard case .archive(let archiveType, _, _) = artifactType else {
            return "archive"
        }
        return archiveType.fileExtension
    }

    public func cancelDownload(taskId: String) {
        if let downloadRequest = activeDownloadRequests[taskId] {
            downloadRequest.cancel()
            activeDownloadRequests.removeValue(forKey: taskId)

            // Track download cancelled
            EventPublisher.shared.track(ModelEvent.downloadCancelled(modelId: taskId))

            logger.info("Cancelled download task: \(taskId)")
        }
    }

    // MARK: - Custom Strategy Support

    /// Register a custom download strategy from host app
    public func registerStrategy(_ strategy: DownloadStrategy) {
        customStrategies.insert(strategy, at: 0) // Custom strategies have priority
        logger.info("Registered custom download strategy")
    }

    /// Refresh strategies from framework adapters (call after registering new adapters)
    public func refreshStrategies() {
        autoRegisterStrategies()
    }

    /// Auto-discover and register strategies from service providers
    private func autoRegisterStrategies() {
        // Download strategies are registered directly by service providers
        // No auto-discovery needed since adapters are removed
        logger.info("[DEBUG] Download strategies are registered directly by service providers")
    }

    /// Helper to download using a custom strategy
    private func downloadModelWithCustomStrategy(_ model: ModelInfo, strategy: DownloadStrategy) async throws -> DownloadTask {
        logger.info("Using custom strategy for model: \(model.id)")

        // Track download started
        EventPublisher.shared.track(ModelEvent.downloadStarted(modelId: model.id))

        let taskId = UUID().uuidString
        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        // Create download task
        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                }

                do {
                    let destinationFolder = try getDestinationFolder(for: model.id, framework: model.preferredFramework)
                    var lastReportedProgress = 0.0

                    let resultURL = try await strategy.download(
                        model: model,
                        to: destinationFolder,
                        progressHandler: { progress in
                            progressContinuation.yield(DownloadProgress(
                                bytesDownloaded: Int64(progress * Double(model.downloadSize ?? 100)),
                                totalBytes: Int64(model.downloadSize ?? 100),
                                state: .downloading
                            ))

                            // Track progress at 10% intervals (analytics only)
                            if progress - lastReportedProgress >= 0.1 {
                                lastReportedProgress = progress
                                EventPublisher.shared.track(ModelEvent.downloadProgress(
                                    modelId: model.id,
                                    progress: progress,
                                    bytesDownloaded: Int64(progress * Double(model.downloadSize ?? 100)),
                                    totalBytes: Int64(model.downloadSize ?? 100)
                                ))
                            }
                        }
                    )

                    // Update progress to completed
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: Int64(model.downloadSize ?? 100),
                        totalBytes: Int64(model.downloadSize ?? 100),
                        state: .completed
                    ))

                    // Update model with local path in registry
                    var updatedModel = model
                    updatedModel.localPath = resultURL
                    ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

                    // Save metadata persistently
                    do {
                        let modelInfoService = await ServiceContainer.shared.modelInfoService
                        try await modelInfoService.saveModel(updatedModel)
                        self.logger.info("Model metadata saved successfully for: \(model.id)")
                    } catch {
                        self.logger.error("Failed to save model metadata for \(model.id): \(error)")
                        // Continue with download completion, but log the error
                    }

                    // Track download completed
                    let durationMs = Date().timeIntervalSince(downloadStartTime) * 1000
                    EventPublisher.shared.track(ModelEvent.downloadCompleted(
                        modelId: model.id,
                        durationMs: durationMs,
                        sizeBytes: model.downloadSize ?? 0
                    ))

                    self.logger.info("Custom strategy download completed", metadata: [
                        "modelId": model.id,
                        "localPath": resultURL.path
                    ])

                    return resultURL
                } catch {
                    // Track download failed
                    EventPublisher.shared.track(ModelEvent.downloadFailed(
                        modelId: model.id,
                        error: error.localizedDescription
                    ))

                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: Int64(model.downloadSize ?? 0),
                        state: .failed(error)
                    ))
                    throw error
                }
            }
        )

        return task
    }

    /// Helper to get destination folder for a model
    private func getDestinationFolder(for modelId: String, framework: InferenceFramework? = nil) throws -> URL {
        if let framework = framework {
            return try ModelPathUtils.getModelFolder(modelId: modelId, framework: framework)
        } else {
            return try ModelPathUtils.getModelFolder(modelId: modelId)
        }
    }

    // MARK: - Helper Methods

    private func calculateDownloadSpeed(progress: Progress) -> String {
        return progressHandler.calculateSpeed(progress: progress)
    }

    private func mapAlamofireError(_ error: AFError) -> Error {
        switch error {
        case .sessionTaskFailed(let underlyingError):
            return DownloadError.networkError(underlyingError)
        case .responseValidationFailed(reason: let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return DownloadError.httpError(code)
            default:
                return DownloadError.invalidResponse
            }
        case .createURLRequestFailed, .invalidURL:
            return DownloadError.invalidURL
        default:
            return DownloadError.unknown
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
}

// MARK: - Extensions for Resumable Downloads

extension AlamofireDownloadService {

    /// Download with resume support
    public func downloadModelWithResume(_ model: ModelInfo, resumeData: Data? = nil) async throws -> DownloadTask {
        guard let downloadURL = model.downloadURL else {
            throw DownloadError.invalidURL
        }

        let taskId = UUID().uuidString
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    self.activeDownloadRequests.removeValue(forKey: taskId)
                }

                return try await self.executeResumableDownload(
                    model: model,
                    downloadURL: downloadURL,
                    taskId: taskId,
                    resumeData: resumeData,
                    progressContinuation: progressContinuation
                )
            }
        )

        return task
    }

    /// Execute a resumable download
    private func executeResumableDownload(
        model: ModelInfo,
        downloadURL: URL,
        taskId: String,
        resumeData: Data?,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Get destination folder (framework is required)
        guard let framework = model.preferredFramework ?? model.compatibleFrameworks.first else {
            logger.error("Model has no associated framework: \(model.id)")
            throw DownloadError.invalidURL
        }
        let fileManager = ServiceContainer.shared.fileManager
        let modelFolder = try fileManager.getModelFolder(for: model.id, framework: framework)
        let destinationURL = URL(fileURLWithPath: modelFolder.path).appendingPathComponent("\(model.id).\(model.format.rawValue)")

        let destination: DownloadRequest.Destination = { _, _ in
            return (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        // Create download request (resume if data available)
        let downloadRequest = createResumableDownloadRequest(
            downloadURL: downloadURL,
            resumeData: resumeData,
            destination: destination
        )

        // Configure request
        configureResumableDownloadRequest(
            downloadRequest: downloadRequest,
            progressContinuation: progressContinuation
        )

        activeDownloadRequests[taskId] = downloadRequest

        // Handle response using continuation
        return try await handleResumableDownloadResponse(
            downloadRequest: downloadRequest,
            model: model,
            progressContinuation: progressContinuation
        )
    }

    /// Create a resumable download request
    private func createResumableDownloadRequest(
        downloadURL: URL,
        resumeData: Data?,
        destination: @escaping DownloadRequest.Destination
    ) -> DownloadRequest {
        if let resumeData = resumeData {
            return session.download(resumingWith: resumeData, to: destination)
        } else {
            return session.download(downloadURL, to: destination)
        }
    }

    /// Configure the resumable download request with progress tracking
    private func configureResumableDownloadRequest(
        downloadRequest: DownloadRequest,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) {
        downloadRequest
            .downloadProgress { progress in
                let downloadProgress = DownloadProgress(
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    state: .downloading
                )
                progressContinuation.yield(downloadProgress)
            }
            .validate()
    }

    /// Handle the resumable download response
    private func handleResumableDownloadResponse(
        downloadRequest: DownloadRequest,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            downloadRequest.response { [weak self] response in
                guard let self = self else {
                    continuation.resume(throwing: DownloadError.unknown)
                    return
                }

                switch response.result {
                case .success(let url):
                    self.handleResumableDownloadSuccess(
                        url: url,
                        model: model,
                        progressContinuation: progressContinuation,
                        continuation: continuation
                    )

                case .failure(let error):
                    self.handleResumableDownloadFailure(
                        error: error,
                        model: model,
                        response: response,
                        progressContinuation: progressContinuation,
                        continuation: continuation
                    )
                }
            }
        }
    }

    /// Handle successful resumable download
    private func handleResumableDownloadSuccess(
        url: URL?,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation,
        continuation: CheckedContinuation<URL, Error>
    ) {
        if let url = url {
            progressContinuation.yield(DownloadProgress(
                bytesDownloaded: model.downloadSize ?? 0,
                totalBytes: model.downloadSize ?? 0,
                state: .completed
            ))

            // Update model with local path in registry
            var updatedModel = model
            updatedModel.localPath = url
            ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

            // Save metadata persistently in a Task
            Task {
                do {
                    let modelInfoService = await ServiceContainer.shared.modelInfoService
                    try await modelInfoService.saveModel(updatedModel)
                    self.logger.info("Model metadata saved successfully for: \(model.id)")
                } catch {
                    self.logger.error("Failed to save model metadata for \(model.id): \(error)")
                }
            }

            continuation.resume(returning: url)
        } else {
            continuation.resume(throwing: DownloadError.invalidResponse)
        }
    }

    /// Handle failed resumable download
    private func handleResumableDownloadFailure(
        error: AFError,
        model: ModelInfo,
        response: DownloadResponse<URL?, AFError>,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation,
        continuation: CheckedContinuation<URL, Error>
    ) {
        // Save resume data if available
        if let resumeData = response.resumeData {
            saveResumeData(resumeData, for: model.id)
        }

        let downloadError = mapAlamofireError(error)
        progressContinuation.yield(DownloadProgress(
            bytesDownloaded: 0,
            totalBytes: model.downloadSize ?? 0,
            state: .failed(downloadError)
        ))
        continuation.resume(throwing: downloadError)
    }

    private func saveResumeData(_ data: Data, for modelId: String) {
        do {
            let fileManager = ServiceContainer.shared.fileManager
            try fileManager.storeCache(key: "resume_\(modelId)", data: data)
        } catch {
            logger.error("Failed to save resume data for \(modelId): \(error)")
        }
    }

    public func getResumeData(for modelId: String) -> Data? {
        do {
            let fileManager = ServiceContainer.shared.fileManager
            return try fileManager.loadCache(key: "resume_\(modelId)")
        } catch {
            logger.error("Failed to load resume data for \(modelId): \(error)")
            return nil
        }
    }
}

// MARK: - Helper Classes

/// Manages download task lifecycle and metadata
private class DownloadTaskManager {
    private let logger = SDKLogger(category: "DownloadTaskManager")

    func createTaskId() -> String {
        return UUID().uuidString
    }

    func logTaskCreation(taskId: String, modelId: String) {
        logger.debug("Created download task", metadata: [
            "taskId": taskId,
            "modelId": modelId
        ])
    }

    func logTaskCompletion(taskId: String, modelId: String) {
        logger.debug("Completed download task", metadata: [
            "taskId": taskId,
            "modelId": modelId
        ])
    }
}

/// Handles download progress tracking and reporting
private class DownloadProgressHandler {
    private let logger = SDKLogger(category: "DownloadProgressHandler")

    func calculateSpeed(progress: Progress) -> String {
        guard progress.totalUnitCount > 0 else { return "0 B/s" }

        // This is a simplified calculation - in production, you'd track time elapsed
        let bytesPerSecond = Double(progress.completedUnitCount) / max(1, progress.estimatedTimeRemaining ?? 1)

        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
    }

    func shouldReportProgress(currentProgress: Double) -> Bool {
        // Report at 10% intervals
        return currentProgress.truncatingRemainder(dividingBy: 10) < 0.1
    }
}

// MARK: - Download Execution Extension

extension AlamofireDownloadService {
    /// Perform the actual download
    func performDownload(
        url: URL,
        destination: URL,
        model: ModelInfo,
        taskId: String,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        let destination: DownloadRequest.Destination = { _, _ in
            return (destination, [.removePreviousFile, .createIntermediateDirectories])
        }

        let downloadRequest = session.download(url, to: destination)
            .downloadProgress { progress in
                let downloadProgress = DownloadProgress(
                    stage: .downloading,
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    stageProgress: progress.fractionCompleted,
                    state: .downloading
                )

                // Log progress at 10% intervals
                let progressPercent = progress.fractionCompleted * 100
                if progressPercent.truncatingRemainder(dividingBy: 10) < 0.1 {
                    self.logger.debug("Download progress", metadata: [
                        "modelId": model.id,
                        "progress": progressPercent,
                        "bytesDownloaded": progress.completedUnitCount,
                        "totalBytes": progress.totalUnitCount,
                        "speed": self.calculateDownloadSpeed(progress: progress)
                    ])

                    EventPublisher.shared.track(ModelEvent.downloadProgress(
                        modelId: model.id,
                        progress: progress.fractionCompleted,
                        bytesDownloaded: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    ))
                }

                progressContinuation.yield(downloadProgress)
            }
            .validate()

        activeDownloadRequests[taskId] = downloadRequest

        return try await withCheckedThrowingContinuation { continuation in
            downloadRequest.response { response in
                switch response.result {
                case .success(let downloadedURL):
                    if let downloadedURL = downloadedURL {
                        continuation.resume(returning: downloadedURL)
                    } else {
                        EventPublisher.shared.track(ModelEvent.downloadFailed(
                            modelId: model.id,
                            error: "Invalid response - no URL returned"
                        ))
                        continuation.resume(throwing: DownloadError.invalidResponse)
                    }

                case .failure(let error):
                    let downloadError = self.mapAlamofireError(error)
                    EventPublisher.shared.track(ModelEvent.downloadFailed(
                        modelId: model.id,
                        error: error.localizedDescription
                    ))
                    self.logger.error("Download failed", metadata: [
                        "modelId": model.id,
                        "url": url.absoluteString,
                        "error": error.localizedDescription,
                        "statusCode": response.response?.statusCode ?? 0
                    ])
                    continuation.resume(throwing: downloadError)
                }
            }
        }
    }

    /// Perform extraction for archive models
    func performExtraction(
        archiveURL: URL,
        destinationFolder: URL,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        guard case .archive(let archiveType, _, _) = model.artifactType else {
            throw DownloadError.extractionFailed("Model does not require extraction")
        }

        let extractionStartTime = Date()

        // Track extraction started
        EventPublisher.shared.track(ModelEvent.extractionStarted(
            modelId: model.id,
            archiveType: archiveType.rawValue
        ))

        logger.info("Starting extraction", metadata: [
            "modelId": model.id,
            "archiveType": archiveType.rawValue,
            "archiveURL": archiveURL.path,
            "destination": destinationFolder.path
        ])

        // Report extraction stage
        progressContinuation.yield(.extraction(modelId: model.id, progress: 0.0))

        do {
            let result = try await extractionService.extract(
                archiveURL: archiveURL,
                to: destinationFolder,
                artifactType: model.artifactType,
                progressHandler: { progress in
                    progressContinuation.yield(.extraction(
                        modelId: model.id,
                        progress: progress,
                        totalBytes: model.downloadSize ?? 0
                    ))

                    // Track extraction progress
                    EventPublisher.shared.track(ModelEvent.extractionProgress(
                        modelId: model.id,
                        progress: progress
                    ))
                }
            )

            let extractionDurationMs = Date().timeIntervalSince(extractionStartTime) * 1000

            // Track extraction completed
            EventPublisher.shared.track(ModelEvent.extractionCompleted(
                modelId: model.id,
                durationMs: extractionDurationMs
            ))

            logger.info("Extraction completed", metadata: [
                "modelId": model.id,
                "modelPath": result.modelPath.path,
                "extractedSize": result.extractedSize,
                "fileCount": result.fileCount,
                "durationMs": extractionDurationMs
            ])

            return result.modelPath
        } catch {
            EventPublisher.shared.track(ModelEvent.extractionFailed(
                modelId: model.id,
                error: error.localizedDescription
            ))
            throw error
        }
    }
}
