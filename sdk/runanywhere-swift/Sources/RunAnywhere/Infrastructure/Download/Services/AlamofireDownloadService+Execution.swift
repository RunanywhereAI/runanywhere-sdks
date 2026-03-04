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
        progressContinuation: AsyncStream<DownloadProgress>.Continuation,
        progressOffset: Double = 0.0,
        progressScale: Double = 1.0
    ) async throws -> URL {
        let destinationURL = destination
        let dest: DownloadRequest.Destination = { _, _ in
            return (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        var lastReportedProgress = -1.0
        let downloadRequest = session.download(url, to: dest)
            .downloadProgress { progress in
                // Apply offset and scale for multi-file downloads
                let scaledProgress = progressOffset + (progress.fractionCompleted * progressScale)
                let downloadProgress = DownloadProgress(
                    stage: .downloading,
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    stageProgress: scaledProgress,
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

                // Track progress at defined intervals (via C++ for routing to EventBus/telemetry)
                let progressValue = progress.fractionCompleted
                if progressValue - lastReportedProgress >= Self.publicProgressIntervalFraction {
                    lastReportedProgress = progressValue
                    CppBridge.Events.emitDownloadProgress(
                        modelId: model.id,
                        progress: progressValue * 100,
                        bytesDownloaded: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
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
                        CppBridge.Events.emitDownloadFailed(modelId: model.id, error: downloadError)
                        continuation.resume(throwing: downloadError)
                    }

                case .failure(let error):
                    let downloadError = self.mapAlamofireError(error)
                    CppBridge.Events.emitDownloadFailed(modelId: model.id, error: downloadError)
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

    /// Perform extraction for archive models (uses native C++ libarchive via rac_extract_archive)
    /// Archive type auto-detection and post-extraction model path finding are handled by C++.
    func performExtraction(
        archiveURL: URL,
        destinationFolder: URL,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        // Use artifact type directly — C++ extraction auto-detects archive format from file contents.
        // If model doesn't have an explicit archive artifact type, construct one with .unknown structure.
        let artifactTypeForExtraction: ModelArtifactType
        if case .archive = model.artifactType {
            artifactTypeForExtraction = model.artifactType
        } else {
            // C++ rac_extract_archive_native() auto-detects archive format, so archive type here
            // is only used for the structure hint passed to post-extraction path finding.
            artifactTypeForExtraction = .archive(.zip, structure: .unknown, expectedFiles: .none)
        }

        let extractionStartTime = Date()

        // Track extraction started via C++ event system
        // Archive type detection is now in C++ — use artifact type if known, otherwise "unknown"
        let archiveTypeString: String
        if case .archive(let type, _, _) = model.artifactType {
            archiveTypeString = type.rawValue
        } else {
            archiveTypeString = "unknown"
        }
        CppBridge.Events.emitExtractionStarted(
            modelId: model.id,
            archiveType: archiveTypeString
        )

        logger.info("Starting extraction", metadata: [
            "modelId": model.id,
            "archiveType": archiveTypeString,
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
                framework: model.framework,
                format: model.format,
                progressHandler: { progress in
                    // Track extraction progress (via C++ for routing to EventBus/telemetry)
                    if progress - lastReportedExtractionProgress >= 0.1 {
                        lastReportedExtractionProgress = progress
                        CppBridge.Events.emitExtractionProgress(
                            modelId: model.id,
                            progress: progress * 100
                        )
                    }

                    progressContinuation.yield(.extraction(
                        modelId: model.id,
                        progress: progress,
                        totalBytes: model.downloadSize ?? 0
                    ))
                }
            )

            let extractionDurationMs = Date().timeIntervalSince(extractionStartTime) * 1000

            // Track extraction completed via C++ event system
            CppBridge.Events.emitExtractionCompleted(
                modelId: model.id,
                durationMs: extractionDurationMs
            )

            logger.info("Extraction completed", metadata: [
                "modelId": model.id,
                "modelPath": result.modelPath.path,
                "extractedSize": result.extractedSize,
                "fileCount": result.fileCount,
                "durationMs": extractionDurationMs
            ])

            return result.modelPath
        } catch {
            CppBridge.Events.emitExtractionFailed(
                modelId: model.id,
                error: SDKError.from(error, category: .download)
            )
            throw error
        }
    }
}
