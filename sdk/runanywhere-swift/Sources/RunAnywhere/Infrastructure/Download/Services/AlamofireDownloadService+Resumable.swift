import Alamofire
import Foundation

// MARK: - Resumable Downloads

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
    func executeResumableDownload(
        model: ModelInfo,
        downloadURL: URL,
        taskId: String,
        resumeData: Data?,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Get destination folder (framework is required - 1:1 mapping)
        let framework = model.framework
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
    func createResumableDownloadRequest(
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
    func configureResumableDownloadRequest(
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
    func handleResumableDownloadResponse(
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
    func handleResumableDownloadSuccess(
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
    func handleResumableDownloadFailure(
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

    func saveResumeData(_ data: Data, for modelId: String) {
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
