import Alamofire
import Foundation

// MARK: - Download Execution

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

        var lastReportedProgress = -1.0
        let downloadRequest = session.download(url, to: destination)
            .downloadProgress { progress in
                let downloadProgress = DownloadProgress(
                    stage: .downloading,
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    stageProgress: progress.fractionCompleted,
                    state: .downloading
                )

                // Log progress at 25% intervals (local logging only)
                let progressPercent = Int(progress.fractionCompleted * 100)
                if progressPercent % 25 == 0 && progressPercent > 0 {
                    self.logger.debug("Download progress", metadata: [
                        "modelId": model.id,
                        "progress": progressPercent,
                        "bytesDownloaded": progress.completedUnitCount,
                        "totalBytes": progress.totalUnitCount,
                        "speed": self.calculateDownloadSpeed(progress: progress)
                    ])
                }

                // Track progress at 10% intervals (public EventBus only - for UI updates)
                let progressValue = progress.fractionCompleted
                if progressValue - lastReportedProgress >= 0.1 {
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
            var lastReportedExtractionProgress: Double = -1.0
            let result = try await extractionService.extract(
                archiveURL: archiveURL,
                to: destinationFolder,
                artifactType: model.artifactType,
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
                error: error.localizedDescription
            ))
            throw error
        }
    }
}
