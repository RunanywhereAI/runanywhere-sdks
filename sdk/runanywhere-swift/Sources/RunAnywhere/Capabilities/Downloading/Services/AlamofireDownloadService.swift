import Foundation
import Alamofire
import Files
import Pulse

/// Simplified download service using Alamofire
public class AlamofireDownloadService: DownloadManager {

    // MARK: - Properties

    private let session: Session
    private var activeDownloadRequests: [String: DownloadRequest] = [:]
    private let logger = SDKLogger(category: "AlamofireDownloadService")

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
    }

    // MARK: - DownloadManager Protocol

    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
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

                                    // Save metadata persistently
                                    Task {
                                        if let dataSyncService = await ServiceContainer.shared.dataSyncService {
                                            try? await dataSyncService.saveModelMetadata(updatedModel)
                                        }
                                    }

                                    self.logger.info("Download completed", metadata: [
                                        "modelId": model.id,
                                        "localPath": url.path,
                                        "fileSize": (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0,
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

    public func activeDownloads() -> [DownloadTask] {
        // Note: We can't return the actual DownloadTask objects as they're created asynchronously
        // This would need refactoring to maintain a proper task registry
        return []
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

                                    // Save metadata persistently
                                    Task {
                                        if let dataSyncService = await ServiceContainer.shared.dataSyncService {
                                            try? await dataSyncService.saveModelMetadata(updatedModel)
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
