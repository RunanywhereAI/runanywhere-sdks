//
//  DownloadAdapter+Execution.swift
//  RunAnywhere SDK
//
//  Transport + extraction helpers for DownloadAdapter.
//
//  Transport runs in C via `rac_http_download_execute` — see
//  `rac_http_download.h`. This extension owns the Swift bridging:
//  cancel-token map, chunk callbacks, and the AsyncStream plumbing
//  that reports progress back to the C++ `CppBridge.Download`
//  manager and to Swift callers.
//

import CRACommons
import Foundation

// MARK: - Download Transport

extension DownloadAdapter {

    /// Progress logging interval (every 10%).
    private static let logProgressIntervalPercent = 10
    /// Public event interval (every 5%).
    private static let publicProgressIntervalFraction = 0.05

    /// Execute a single file download using the canonical C runner.
    ///
    /// - Returns: The destination URL on success (same as the input
    ///   `destination` parameter, mirroring the previous Alamofire
    ///   contract that returned the final download location).
    func performDownload(
        url: URL,
        destination: URL,
        model: ModelInfo,
        taskId: String,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation,
        progressOffset: Double = 0.0,
        progressScale: Double = 1.0
    ) async throws -> URL {
        // Prepare destination directory.
        let destinationDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        let cancelToken = CancelToken()
        storeCancelToken(cancelToken, forKey: taskId)

        let progressState = DownloadProgressState(
            modelId: model.id,
            totalHint: model.downloadSize ?? 0,
            taskId: taskId,
            progressOffset: progressOffset,
            progressScale: progressScale,
            logInterval: Self.logProgressIntervalPercent,
            publicInterval: Self.publicProgressIntervalFraction,
            progressContinuation: progressContinuation,
            cancelToken: cancelToken,
            logger: logger
        )

        let urlString = url.absoluteString
        let destinationPath = destination.path
        let timeoutMs = Int32(max(0, min(Double(Int32.max), configuration.timeout * 1000)))

        let adapter = self
        let (status, httpStatus): (rac_http_download_status_t, Int32) = try await withCheckedThrowingContinuation { continuation in
            adapter.downloadQueue.async {
                let progressStateRef = Unmanaged.passRetained(progressState)
                defer { progressStateRef.release() }

                urlString.withCString { urlC in
                    destinationPath.withCString { destC in
                        var request = rac_http_download_request_t(
                            url: urlC,
                            destination_path: destC,
                            headers: nil,
                            header_count: 0,
                            timeout_ms: timeoutMs,
                            follow_redirects: RAC_TRUE,
                            resume_from_byte: 0,
                            expected_sha256_hex: nil
                        )

                        var httpStatusOut: Int32 = 0
                        let status = rac_http_download_execute(
                            &request,
                            downloadProgressTrampoline,
                            progressStateRef.toOpaque(),
                            &httpStatusOut
                        )
                        continuation.resume(returning: (status, httpStatusOut))
                    }
                }
            }
        }

        if status != RAC_HTTP_DL_OK {
            let error = mapDownloadError(status, httpStatus: httpStatus)
            CppBridge.Events.emitDownloadFailed(modelId: model.id, error: error)
            logger.error("Download failed", metadata: [
                "modelId": model.id,
                "url": url.absoluteString,
                "error": error.message,
                "statusCode": httpStatus,
                "downloadStatus": Int(status.rawValue)
            ])
            // Clean up partial destination on failure (matches
            // previous Alamofire behaviour where the download moved
            // its tmp file only on success).
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return destination
    }

    /// Perform extraction for archive models (uses native C++
    /// libarchive via `rac_extract_archive`). Archive type
    /// auto-detection and post-extraction model path finding are
    /// handled by C++.
    func performExtraction(
        archiveURL: URL,
        destinationFolder: URL,
        model: ModelInfo,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        let artifactTypeForExtraction: ModelArtifactType
        if case .archive = model.artifactType {
            artifactTypeForExtraction = model.artifactType
        } else {
            artifactTypeForExtraction = .archive(.zip, structure: .unknown, expectedFiles: .none)
        }

        let extractionStartTime = Date()

        let archiveTypeString: String
        if case .archive(let type, _, _) = model.artifactType {
            archiveTypeString = type.fileExtension
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
                error: SDKException.from(error, category: .network)
            )
            throw error
        }
    }
}

// MARK: - Progress State (retained through the C call)

/// Boxed state passed through the C trampoline as an opaque pointer.
/// Class instance is `Unmanaged.passRetained`d for the duration of
/// the download so the raw pointer remains valid inside curl's
/// progress callback.
final class DownloadProgressState {
    let modelId: String
    let totalHint: Int64
    let taskId: String
    let progressOffset: Double
    let progressScale: Double
    let logInterval: Int
    let publicInterval: Double
    let progressContinuation: AsyncStream<DownloadProgress>.Continuation
    let cancelToken: DownloadAdapter.CancelToken
    let logger: SDKLogger

    var lastReportedProgress: Double = -1.0

    init(
        modelId: String,
        totalHint: Int64,
        taskId: String,
        progressOffset: Double,
        progressScale: Double,
        logInterval: Int,
        publicInterval: Double,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation,
        cancelToken: DownloadAdapter.CancelToken,
        logger: SDKLogger
    ) {
        self.modelId = modelId
        self.totalHint = totalHint
        self.taskId = taskId
        self.progressOffset = progressOffset
        self.progressScale = progressScale
        self.logInterval = logInterval
        self.publicInterval = publicInterval
        self.progressContinuation = progressContinuation
        self.cancelToken = cancelToken
        self.logger = logger
    }
}

/// C trampoline for `rac_http_download_progress_fn`. Must be a bare
/// function pointer (no captures) — all context is forwarded via the
/// opaque user-data pointer.
private func downloadProgressTrampoline(
    bytesWritten: UInt64,
    totalBytes: UInt64,
    userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let userData = userData else { return RAC_TRUE }
    let state = Unmanaged<DownloadProgressState>.fromOpaque(userData).takeUnretainedValue()

    if state.cancelToken.isCancelled {
        return RAC_FALSE
    }

    let totalReported = Int64(min(UInt64(Int64.max), totalBytes))
    let completed = Int64(min(UInt64(Int64.max), bytesWritten))
    let effectiveTotal = totalReported > 0 ? totalReported : state.totalHint

    let fraction: Double
    if effectiveTotal > 0 {
        fraction = min(1.0, max(0.0, Double(completed) / Double(effectiveTotal)))
    } else {
        fraction = 0.0
    }

    let scaledProgress = state.progressOffset + (fraction * state.progressScale)
    let progress = DownloadProgress(
        modelId: state.modelId,
        stage: .downloading,
        bytesDownloaded: completed,
        totalBytes: effectiveTotal,
        stageProgress: scaledProgress,
        state: .downloading
    )

    let modelId = state.modelId
    let taskId = state.taskId

    Task {
        await CppBridge.Download.shared.updateProgress(
            taskId: taskId,
            bytesDownloaded: completed,
            totalBytes: effectiveTotal
        )
    }

    let progressPercent = Int(fraction * 100)
    if progressPercent.isMultiple(of: state.logInterval) && progressPercent > 0 {
        state.logger.debug("Download progress", metadata: [
            "modelId": modelId,
            "progress": progressPercent,
            "bytesDownloaded": completed,
            "totalBytes": effectiveTotal
        ])
    }

    if fraction - state.lastReportedProgress >= state.publicInterval {
        state.lastReportedProgress = fraction
        CppBridge.Events.emitDownloadProgress(
            modelId: modelId,
            progress: fraction * 100,
            bytesDownloaded: completed,
            totalBytes: effectiveTotal
        )
    }

    state.progressContinuation.yield(progress)
    return RAC_TRUE
}
