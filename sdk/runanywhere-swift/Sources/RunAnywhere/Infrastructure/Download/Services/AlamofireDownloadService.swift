// swiftlint:disable file_length
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

    // MARK: - Custom Download Strategies

    /// Storage for custom download strategies provided by host app
    private var customStrategies: [DownloadStrategy] = []

    // MARK: - Initialization

    public init(configuration: DownloadConfiguration = DownloadConfiguration()) {
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

    // swiftlint:disable:next function_body_length
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        // Check if any custom strategy can handle this model
        logger.info("[DEBUG] Checking strategies for model \(model.id), framework: \(model.preferredFramework?.rawValue ?? "none")")
        logger.info("[DEBUG] Available custom strategies: \(customStrategies.count)")

        for (index, strategy) in customStrategies.enumerated() {
            let canHandle = strategy.canHandle(model: model)
            logger.info("[DEBUG] Strategy \(index): \(type(of: strategy)) canHandle=\(canHandle)")
            if canHandle {
                logger.info("[DEBUG] Using custom strategy \(type(of: strategy)) for model \(model.id)")
                return try await downloadModelWithCustomStrategy(model, strategy: strategy)
            }
        }

        logger.info("[DEBUG] No custom strategy found for model \(model.id), using default download")
        // No custom strategy found, use default download
        guard let downloadURL = model.downloadURL else {
            throw DownloadError.invalidURL
        }

        let taskId = UUID().uuidString
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

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
                    // Use SimplifiedFileManager for destination path
                    let fileManager = ServiceContainer.shared.fileManager
                    // Use framework-specific folder if available
                    let modelFolder: Folder
                    if let framework = model.preferredFramework ?? model.compatibleFrameworks.first {
                        modelFolder = try fileManager.getModelFolder(for: model.id, framework: framework)
                    } else {
                        modelFolder = try fileManager.getModelFolder(for: model.id)
                    }
                    let destinationURL = URL(fileURLWithPath: modelFolder.path).appendingPathComponent("\(model.id).\(model.format.rawValue)")

                    // Configure destination
                    let destination: DownloadRequest.Destination = { _, _ in
                        return (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
                    }

                    // Log download start
                    self.logger.info("Starting download", metadata: [
                        "modelId": model.id,
                        "url": downloadURL.absoluteString,
                        "expectedSize": model.downloadSize ?? 0,
                        "destination": destinationURL.path
                    ])

                    // Network logging is handled automatically by Alamofire + Pulse integration

                    // Create download request
                    let downloadRequest = self.session.download(downloadURL, to: destination)
                        .downloadProgress { progress in
                            let downloadProgress = DownloadProgress(
                                bytesDownloaded: progress.completedUnitCount,
                                totalBytes: progress.totalUnitCount,
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
                            }

                            progressContinuation.yield(downloadProgress)
                        }
                        .validate()

                    // Store active download
                    self.activeDownloadRequests[taskId] = downloadRequest

                    // Wait for completion using continuation
                    return try await withCheckedThrowingContinuation { continuation in
                        downloadRequest.response { response in
                            switch response.result {
                            case .success(let url):
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

                                    self.logger.info("Download completed", metadata: [
                                        "modelId": model.id,
                                        "localPath": url.path,
                                        "fileSize": FileOperationsUtilities.fileSize(at: url) ?? 0,
                                        "duration": response.metrics?.taskInterval.duration ?? 0
                                    ])
                                    continuation.resume(returning: url)
                                } else {
                                    continuation.resume(throwing: DownloadError.invalidResponse)
                                }

                            case .failure(let error):
                                let downloadError = self.mapAlamofireError(error)

                                self.logger.error("Download failed", metadata: [
                                    "modelId": model.id,
                                    "url": downloadURL.absoluteString,
                                    "error": error.localizedDescription,
                                    "errorType": String(describing: type(of: error)),
                                    "statusCode": response.response?.statusCode ?? 0
                                ])

                                progressContinuation.yield(DownloadProgress(
                                    bytesDownloaded: 0,
                                    totalBytes: model.downloadSize ?? 0,
                                    state: .failed(downloadError)
                                ))
                                continuation.resume(throwing: downloadError)
                            }
                        }
                    }
                } catch {
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: model.downloadSize ?? 0,
                        state: .failed(error)
                    ))
                    throw error
                }
            }
        )

        return task
    }

    public func cancelDownload(taskId: String) {
        if let downloadRequest = activeDownloadRequests[taskId] {
            downloadRequest.cancel()
            activeDownloadRequests.removeValue(forKey: taskId)
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

    /// Auto-discover and register strategies from framework adapters
    private func autoRegisterStrategies() {
        let adapters = ServiceContainer.shared.adapterRegistry.getRegisteredAdapters()
        var registeredCount = 0

        logger.info("[DEBUG] Auto-registering strategies from \(adapters.count) adapters")

        for (framework, adapter) in adapters {
            if let strategy = adapter.getDownloadStrategy() {
                // Auto-discovered strategies go after manually registered ones
                customStrategies.append(strategy)
                registeredCount += 1
                logger.info("[DEBUG] Auto-registered download strategy \(type(of: strategy)) from \(framework.rawValue) adapter")
            } else {
                logger.info("[DEBUG] No download strategy from \(framework.rawValue) adapter")
            }
        }

        if registeredCount > 0 {
            logger.info("Auto-registered \(registeredCount) download strategies from adapters")
        } else {
            logger.info("[DEBUG] No strategies auto-registered")
        }
    }

    /// Helper to download using a custom strategy
    private func downloadModelWithCustomStrategy(_ model: ModelInfo, strategy: DownloadStrategy) async throws -> DownloadTask {
        logger.info("Using custom strategy for model: \(model.id)")

        let taskId = UUID().uuidString
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

                    let resultURL = try await strategy.download(
                        model: model,
                        to: destinationFolder,
                        progressHandler: { progress in
                            progressContinuation.yield(DownloadProgress(
                                bytesDownloaded: Int64(progress * Double(model.downloadSize ?? 100)),
                                totalBytes: Int64(model.downloadSize ?? 100),
                                state: .downloading
                            ))
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

                    self.logger.info("Custom strategy download completed", metadata: [
                        "modelId": model.id,
                        "localPath": resultURL.path
                    ])

                    return resultURL
                } catch {
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
    private func getDestinationFolder(for modelId: String, framework: LLMFramework? = nil) throws -> URL {
        if let framework = framework {
            return try ModelPathUtils.getModelFolder(modelId: modelId, framework: framework)
        } else {
            return try ModelPathUtils.getModelFolder(modelId: modelId)
        }
    }

    // MARK: - Helper Methods

    private func calculateDownloadSpeed(progress: Progress) -> String {
        // Simple speed calculation - could be enhanced with time-based tracking
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
    public func downloadModelWithResume(_ model: ModelInfo, resumeData: Data? = nil) async throws -> DownloadTask { // swiftlint:disable:this function_body_length
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

                do {
                    // Use SimplifiedFileManager for destination path
                    let fileManager = ServiceContainer.shared.fileManager
                    // Use framework-specific folder if available
                    let modelFolder: Folder
                    if let framework = model.preferredFramework ?? model.compatibleFrameworks.first {
                        modelFolder = try fileManager.getModelFolder(for: model.id, framework: framework)
                    } else {
                        modelFolder = try fileManager.getModelFolder(for: model.id)
                    }
                    let destinationURL = URL(fileURLWithPath: modelFolder.path).appendingPathComponent("\(model.id).\(model.format.rawValue)")

                    let destination: DownloadRequest.Destination = { _, _ in
                        return (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
                    }

                    // Create download request (resume if data available)
                    let downloadRequest: DownloadRequest
                    if let resumeData = resumeData {
                        downloadRequest = self.session.download(resumingWith: resumeData, to: destination)
                    } else {
                        downloadRequest = self.session.download(downloadURL, to: destination)
                    }

                    // Configure request
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

                    self.activeDownloadRequests[taskId] = downloadRequest

                    // Handle response using continuation
                    return try await withCheckedThrowingContinuation { continuation in
                        downloadRequest.response { response in
                            switch response.result {
                            case .success(let url):
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

                            case .failure(let error):
                                // Save resume data if available
                                if let resumeData = response.resumeData {
                                    // Store resume data for later use
                                    self.saveResumeData(resumeData, for: model.id)
                                }

                                let downloadError = self.mapAlamofireError(error)
                                progressContinuation.yield(DownloadProgress(
                                    bytesDownloaded: 0,
                                    totalBytes: model.downloadSize ?? 0,
                                    state: .failed(downloadError)
                                ))
                                continuation.resume(throwing: downloadError)
                            }
                        }
                    }
                } catch {
                    throw error
                }
            }
        )

        return task
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
