import Alamofire
import Foundation

// MARK: - Download Execution

extension AlamofireDownloadService {

    /// Progress logging interval (every 10%)
    private static let logProgressIntervalPercent = 10
    /// Public event interval (every 5%)
    private static let publicProgressIntervalFraction = 0.05

    /// Perform the actual download using Alamofire
    func performDownload(
        url: URL,
        destination: URL,
        model: ModelInfo,
        taskId: String,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        let destinationURL = destination
        let dest: DownloadRequest.Destination = { _, _ in
            return (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        var lastReportedProgress = -1.0
        let downloadRequest = session.download(url, to: dest)
            .downloadProgress { progress in
                let downloadProgress = DownloadProgress(
                    stage: .downloading,
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    stageProgress: progress.fractionCompleted,
                    state: .downloading
                )

                // Update C++ bridge with progress
                Task {
                    await CppBridge.Download.shared.updateProgress(
                        taskId: taskId,
                        bytesDownloaded: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
                }

                // Log progress at defined intervals (local logging only)
                let progressPercent = Int(progress.fractionCompleted * 100)
                if progressPercent.isMultiple(of: Self.logProgressIntervalPercent) && progressPercent > 0 {
                    self.logger.debug("Download progress", metadata: [
                        "modelId": model.id,
                        "progress": progressPercent,
                        "bytesDownloaded": progress.completedUnitCount,
                        "totalBytes": progress.totalUnitCount
                    ])
                }

                // Track progress at defined intervals (public EventBus only - for UI updates)
                let progressValue = progress.fractionCompleted
                if progressValue - lastReportedProgress >= Self.publicProgressIntervalFraction {
                    lastReportedProgress = progressValue
                    EventPublisher.shared.track(ModelEvent.downloadProgress(
                        modelId: model.id,
                        progress: progressValue,
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
                        let downloadError = SDKError.download(.invalidResponse, "Invalid response - no URL returned")
                        EventPublisher.shared.track(ModelEvent.downloadFailed(modelId: model.id, error: downloadError))
                        continuation.resume(throwing: downloadError)
                    }

                case .failure(let error):
                    let downloadError = self.mapAlamofireError(error)
                    EventPublisher.shared.track(ModelEvent.downloadFailed(modelId: model.id, error: downloadError))
                    self.logger.error("Download failed", metadata: [
                        "modelId": model.id,
                        "url": url.absoluteString,
                        "error": downloadError.message,
                        "statusCode": response.response?.statusCode ?? 0
                    ])
                    continuation.resume(throwing: downloadError)
                }
            }
        }
    }

    /// Perform extraction for archive models (platform-specific - uses SWCompression)
    func performExtraction(
        archiveURL: URL,
        destinationFolder: URL,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Determine archive type from model artifact type or infer from archive URL/download URL
        let archiveType: ArchiveType
        let artifactTypeForExtraction: ModelArtifactType

        if case .archive(let type, let structure, let expectedFiles) = model.artifactType {
            archiveType = type
            artifactTypeForExtraction = model.artifactType
        } else if let inferredType = ArchiveType.from(url: archiveURL) {
            // Infer from downloaded archive file path
            archiveType = inferredType
            artifactTypeForExtraction = .archive(inferredType, structure: .unknown, expectedFiles: .none)
            logger.info("Inferred archive type from file path: \(inferredType.rawValue)")
        } else if let originalDownloadURL = model.downloadURL,
                  let inferredType = ArchiveType.from(url: originalDownloadURL) {
            // Infer from original download URL
            archiveType = inferredType
            artifactTypeForExtraction = .archive(inferredType, structure: .unknown, expectedFiles: .none)
            logger.info("Inferred archive type from download URL: \(inferredType.rawValue)")
        } else {
            throw SDKError.download(.extractionFailed, "Could not determine archive type for model: \(model.id)")
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
            var lastReportedExtractionProgress: Double = -1.0
            let result = try await extractionService.extract(
                archiveURL: archiveURL,
                to: destinationFolder,
                artifactType: artifactTypeForExtraction,
                progressHandler: { progress in
                    // Track extraction progress (public EventBus only - for UI updates)
                    if progress - lastReportedExtractionProgress >= 0.1 {
                        lastReportedExtractionProgress = progress
                        EventPublisher.shared.track(ModelEvent.extractionProgress(
                            modelId: model.id,
                            progress: progress
                        ))
                    }

                    progressContinuation.yield(.extraction(
                        modelId: model.id,
                        progress: progress,
                        totalBytes: model.downloadSize ?? 0
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
                error: SDKError.from(error, category: .download)
            ))
            throw error
        }
    }
}
