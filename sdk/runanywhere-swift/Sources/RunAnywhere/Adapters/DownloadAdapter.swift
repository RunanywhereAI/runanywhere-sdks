//
//  DownloadAdapter.swift
//  RunAnywhere SDK
//
//  Swift-side orchestrator for model downloads. HTTP transport runs
//  in C++ via `rac_http_download_execute` (libcurl); Swift retains
//  only the pieces the C side cannot own natively: `AsyncStream`
//  bridging, extraction dispatch, multi-file composition, and
//  progress-event forwarding to the C++ `CppBridge.Download` manager.
//
//  Replaces the prior Alamofire-based `AlamofireDownloadService`.
//

import CRACommons
import Files
import Foundation
import os

/// DownloadAdapter — thin Swift wrapper over the canonical C download
/// runner. Drop-in replacement for `AlamofireDownloadService`.
public class DownloadAdapter: @unchecked Sendable {

    // MARK: - Shared Instance

    public static let shared = DownloadAdapter()

    // MARK: - Cancellation

    /// One `CancelToken` per active task. The C progress callback
    /// polls it to signal curl to abort (returns `RAC_FALSE`).
    final class CancelToken {
        // Per CLAUDE.md: NSLock is forbidden. `OSAllocatedUnfairLock` gives
        // us synchronous Bool access from the C progress callback path.
        private let cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)

        func cancel() {
            cancelled.withLock { $0 = true }
        }

        var isCancelled: Bool {
            cancelled.withLock { $0 }
        }
    }

    // MARK: - Properties

    private var activeCancelTokens: [String: CancelToken] = [:]
    private let tokensQueue = DispatchQueue(label: "com.runanywhere.download.tokens")
    let logger = SDKLogger(category: "DownloadAdapter")

    /// Serial queue for running blocking curl downloads off the
    /// Swift concurrency pool.
    let downloadQueue = DispatchQueue(
        label: "com.runanywhere.download.transport",
        qos: .userInitiated,
        attributes: .concurrent
    )

    let configuration: DownloadConfiguration

    // MARK: - Services

    /// Extraction service for handling archive extraction.
    let extractionService: ExtractionServiceProtocol

    // MARK: - Initialization

    public init(
        configuration: DownloadConfiguration = DownloadConfiguration(),
        extractionService: ExtractionServiceProtocol = DefaultExtractionService()
    ) {
        self.configuration = configuration
        self.extractionService = extractionService
    }

    // MARK: - Download API

    /// Download a model.
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        logger.info("Starting artifact-based download for model \(model.id)", metadata: [
            "artifactType": model.artifactType.displayName,
            "requiresExtraction": model.artifactType.requiresExtraction
        ])

        return try await downloadModelWithArtifactType(model)
    }

    public func cancelDownload(taskId: String) {
        let token: CancelToken? = tokensQueue.sync {
            guard let token = activeCancelTokens[taskId] else { return nil }
            activeCancelTokens.removeValue(forKey: taskId)
            return token
        }

        if let token = token {
            token.cancel()

            Task {
                try? await CppBridge.Download.shared.cancelDownload(taskId: taskId)
            }
            CppBridge.Events.emitDownloadCancelled(modelId: taskId)
            logger.info("Cancelled download task: \(taskId)")
        }
    }

    // MARK: - Public Methods

    /// Pause all active downloads.
    ///
    /// The curl-backed transport does not support pause/resume for
    /// in-flight synchronous downloads; the call is forwarded to the
    /// C++ download manager so higher-level state stays consistent
    /// with prior Alamofire behaviour.
    public func pauseAll() {
        Task {
            try? await CppBridge.Download.shared.pauseAll()
        }
        logger.info("Paused all downloads")
    }

    /// Resume all paused downloads.
    public func resumeAll() {
        Task {
            try? await CppBridge.Download.shared.resumeAll()
        }
        logger.info("Resumed all downloads")
    }

    public func isHealthy() -> Bool {
        true
    }

    // MARK: - Internal Download Methods

    /// Download model using artifact-type-based approach.
    func downloadModelWithArtifactType(_ model: ModelInfo) async throws -> DownloadTask {
        // Multi-file models route through the dedicated path.
        if case .multiFile(var files) = model.artifactType {
            if files.isEmpty, let cachedFiles = RunAnywhere.getMultiFileDescriptors(forModelId: model.id) {
                files = cachedFiles
                logger.info("Retrieved \(files.count) file descriptors from cache for model: \(model.id)")
            }
            return try await downloadMultiFileModel(model, files: files)
        }

        guard let downloadURL = model.downloadURL else {
            let downloadError = SDKException.download(.invalidInput, "Invalid download URL for model: \(model.id)")
            CppBridge.Events.emitDownloadFailed(modelId: model.id, error: downloadError)
            throw downloadError
        }

        CppBridge.Events.emitDownloadStarted(modelId: model.id, totalBytes: model.downloadSize ?? 0)

        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        var requiresExtraction = model.artifactType.requiresExtraction
        if !requiresExtraction, CppBridge.Download.downloadRequiresExtraction(url: downloadURL) {
            logger.info("URL indicates archive but artifact type doesn't require extraction. Inferring extraction needed.")
            requiresExtraction = true
        }

        logger.info("Computing download path for model: \(model.id), framework: \(model.framework.wireString) (\(model.framework.displayName))")
        let destinationFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)
        logger.info("Destination folder: \(destinationFolder.path)")

        let taskId = try await CppBridge.Download.shared.startDownload(
            modelId: model.id,
            url: downloadURL,
            destinationPath: destinationFolder,
            requiresExtraction: requiresExtraction
        ) { progress in
            progressContinuation.yield(progress)
        }

        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    self.removeCancelToken(forKey: taskId)
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
                    await CppBridge.Download.shared.markFailed(
                        taskId: taskId,
                        error: SDKException.from(error, category: .network)
                    )
                    progressContinuation.yield(.failed(error, bytesDownloaded: 0, totalBytes: model.downloadSize ?? 0))
                    throw error
                }
            }
        )

        return task
    }

    // MARK: - Multi-File Download

    /// Download a model that consists of multiple separate files.
    private func downloadMultiFileModel(_ model: ModelInfo, files: [ModelFileDescriptor]) async throws -> DownloadTask {
        guard !files.isEmpty else {
            throw SDKException.download(.invalidInput, "No files specified for multi-file model: \(model.id)")
        }

        logger.info("Starting multi-file download for \(model.id) with \(files.count) files")
        CppBridge.Events.emitDownloadStarted(modelId: model.id, totalBytes: model.downloadSize ?? 0)

        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()
        let destinationFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)
        let taskId = "download-multifile-\(model.id)-\(UUID().uuidString.prefix(8))"

        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    self.removeCancelToken(forKey: taskId)
                }

                do {
                    var totalBytesDownloaded: Int64 = 0
                    let fileCount = files.count

                    for (index, fileDescriptor) in files.enumerated() {
                        let fileDestination = destinationFolder.appendingPathComponent(fileDescriptor.filename)
                        logger.info("Downloading file \(index + 1)/\(fileCount): \(fileDescriptor.filename)")

                        _ = try await self.performDownload(
                            url: fileDescriptor.url,
                            destination: fileDestination,
                            model: model,
                            taskId: "\(taskId)-\(index)",
                            progressContinuation: progressContinuation,
                            progressOffset: Double(index) / Double(fileCount),
                            progressScale: 1.0 / Double(fileCount)
                        )

                        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileDestination.path),
                           let size = attrs[.size] as? Int64 {
                            totalBytesDownloaded += size
                        }

                        logger.info("Completed file \(index + 1)/\(fileCount): \(fileDescriptor.filename)")
                    }

                    CppBridge.Events.emitDownloadCompleted(
                        modelId: model.id,
                        durationMs: Date().timeIntervalSince(downloadStartTime) * 1000,
                        sizeBytes: totalBytesDownloaded
                    )

                    try await CppBridge.ModelRegistry.shared.updateDownloadStatus(
                        modelId: model.id,
                        localPath: destinationFolder
                    )

                    let totalTime = Date().timeIntervalSince(downloadStartTime)
                    logger.info("Multi-file download complete for \(model.id): \(files.count) files in \(String(format: "%.1f", totalTime))s")

                    progressContinuation.yield(.completed(totalBytes: totalBytesDownloaded))

                    return destinationFolder
                } catch {
                    CppBridge.Events.emitDownloadFailed(modelId: model.id, error: SDKException.from(error, category: .network))
                    progressContinuation.yield(.failed(error, bytesDownloaded: 0, totalBytes: model.downloadSize ?? 0))
                    throw error
                }
            }
        )

        return task
    }

    /// Execute the complete download workflow for artifact-based downloads.
    func executeArtifactDownload(
        model: ModelInfo,
        downloadURL: URL,
        taskId: String,
        requiresExtraction: Bool,
        downloadStartTime: Date,
        destinationFolder: URL,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        let downloadDestination = determineDownloadDestination(
            for: model,
            modelFolderURL: destinationFolder,
            requiresExtraction: requiresExtraction
        )

        logger.info("Starting download", metadata: [
            "modelId": model.id,
            "url": downloadURL.absoluteString,
            "expectedSize": model.downloadSize ?? 0,
            "destination": downloadDestination.path,
            "requiresExtraction": requiresExtraction,
        ])

        let downloadedURL = try await performDownload(
            url: downloadURL,
            destination: downloadDestination,
            model: model,
            taskId: taskId,
            progressContinuation: progressContinuation
        )

        await CppBridge.Download.shared.markComplete(taskId: taskId, downloadedPath: downloadedURL)

        let finalModelPath = try await handlePostDownloadProcessing(
            downloadedURL: downloadedURL,
            modelFolderURL: destinationFolder,
            model: model,
            requiresExtraction: requiresExtraction,
            progressContinuation: progressContinuation
        )

        try await updateModelMetadata(model: model, localPath: finalModelPath)
        trackDownloadCompletion(
            model: model,
            finalPath: finalModelPath,
            startTime: downloadStartTime,
            progressContinuation: progressContinuation
        )
        return finalModelPath
    }

    /// Determine the download destination using C++ path utilities.
    private func determineDownloadDestination(
        for model: ModelInfo,
        modelFolderURL: URL,
        requiresExtraction: Bool
    ) -> URL {
        if let downloadURL = model.downloadURL,
           let result = CppBridge.Download.computeDownloadDestination(
               modelId: model.id,
               downloadURL: downloadURL,
               framework: model.framework,
               format: model.format
           ) {
            return result.path
        }
        return modelFolderURL.appendingPathComponent("\(model.id).\(model.format.wireString)")
    }

    /// Handle post-download processing (extraction if needed).
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
            try? FileManager.default.removeItem(at: downloadedURL)
            return finalPath
        } else {
            return downloadedURL
        }
    }

    /// Update model metadata via C++ registry.
    private func updateModelMetadata(model: ModelInfo, localPath: URL) async throws {
        var updatedModel = model
        updatedModel.localPath = localPath
        try await CppBridge.ModelRegistry.shared.save(updatedModel)
        logger.info("Model metadata saved successfully for: \(model.id)")
    }

    /// Track download completion with analytics.
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

        progressContinuation.yield(.completed(totalBytes: model.downloadSize ?? fileSize))

        logger.info("Download completed", metadata: [
            "modelId": model.id,
            "localPath": finalPath.path,
            "fileSize": fileSize
        ])
    }

    // MARK: - Thread-Safe Token Management

    func storeCancelToken(_ token: CancelToken, forKey key: String) {
        tokensQueue.sync { activeCancelTokens[key] = token }
    }

    func removeCancelToken(forKey key: String) {
        tokensQueue.sync { _ = activeCancelTokens.removeValue(forKey: key) }
    }

    // MARK: - Error Mapping

    /// Map a `rac_http_download_status_t` to the matching SDKException.
    func mapDownloadError(_ status: rac_http_download_status_t, httpStatus: Int32) -> SDKException {
        switch status {
        case RAC_HTTP_DL_OK:
            return SDKException.download(.unknown, "Unexpected success status in error mapping")
        case RAC_HTTP_DL_NETWORK_ERROR:
            return SDKException.download(.networkError, "Network error during download")
        case RAC_HTTP_DL_FILE_ERROR:
            return SDKException.download(.fileWriteFailed, "File system error during download")
        case RAC_HTTP_DL_INSUFFICIENT_STORAGE:
            return SDKException.download(.insufficientStorage, "Insufficient storage for download")
        case RAC_HTTP_DL_INVALID_URL:
            return SDKException.download(.invalidInput, "Invalid download URL")
        case RAC_HTTP_DL_CHECKSUM_FAILED:
            return SDKException.download(.checksumMismatch, "Checksum verification failed")
        case RAC_HTTP_DL_CANCELLED:
            return SDKException.download(.downloadFailed, "Download cancelled")
        case RAC_HTTP_DL_SERVER_ERROR:
            return SDKException.download(.httpError, "Server error (HTTP \(httpStatus))")
        case RAC_HTTP_DL_TIMEOUT:
            return SDKException.download(.networkError, "Download timed out")
        case RAC_HTTP_DL_NETWORK_UNAVAILABLE:
            return SDKException.download(.networkError, "Network unavailable")
        case RAC_HTTP_DL_DNS_ERROR:
            return SDKException.download(.networkError, "DNS resolution failed")
        case RAC_HTTP_DL_SSL_ERROR:
            return SDKException.download(.networkError, "SSL/TLS error")
        default:
            return SDKException.download(.unknown, "Unknown download error (rc=\(status.rawValue), http=\(httpStatus))")
        }
    }
}
