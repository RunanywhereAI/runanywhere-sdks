//
//  CppBridge+Download.swift
//  RunAnywhere SDK
//
//  Download manager bridge extension for C++ interop.
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Download Bridge

private enum DownloadProtoABI {
    typealias ProtoFunction = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias ProgressCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SetProgressCallback = @convention(c) (
        ProgressCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let setProgressCallback = NativeProtoABI.load(
        "rac_download_set_progress_proto_callback",
        as: SetProgressCallback.self
    )
    static let plan = NativeProtoABI.load("rac_download_plan_proto", as: ProtoFunction.self)
    static let start = NativeProtoABI.load("rac_download_start_proto", as: ProtoFunction.self)
    static let cancel = NativeProtoABI.load("rac_download_cancel_proto", as: ProtoFunction.self)
    static let resume = NativeProtoABI.load("rac_download_resume_proto", as: ProtoFunction.self)
    static let pollProgress = NativeProtoABI.load(
        "rac_download_progress_poll_proto",
        as: ProtoFunction.self
    )
}

private final class DownloadProtoProgressBox {
    let continuation: AsyncStream<RADownloadProgress>.Continuation

    init(continuation: AsyncStream<RADownloadProgress>.Continuation) {
        self.continuation = continuation
    }
}

private func downloadProtoProgressCallback(
    protoBytes: UnsafePointer<UInt8>?,
    protoSize: Int,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData, let protoBytes, protoSize > 0 else { return }
    let box = Unmanaged<DownloadProtoProgressBox>.fromOpaque(userData).takeUnretainedValue()
    if let progress = try? RADownloadProgress(
        serializedBytes: Data(bytes: protoBytes, count: protoSize)
    ) {
        box.continuation.yield(progress)
    }
}

extension CppBridge {

    /// Download manager bridge
    /// Wraps C++ rac_download.h functions for download orchestration
    public actor Download {

        /// Shared download manager instance
        public static let shared = Download()

        // MARK: - Download Orchestrator Utilities (stateless, nonisolated)

        /// Find model path after archive extraction using C++ rac_find_model_path_after_extraction().
        /// Consolidates Swift findModelPath/findNestedDirectory/findSingleModelFile into one C++ call.
        public static func findModelPathAfterExtraction(
            extractedDir: URL,
            structure: ArchiveStructure,
            framework: InferenceFramework,
            format: ModelFormat
        ) -> URL? {
            var outPath = [CChar](repeating: 0, count: 4096)

            let result = extractedDir.path.withCString { dir in
                rac_find_model_path_after_extraction(
                    dir,
                    structure.toC(),
                    framework.toC(),
                    format.toC(),
                    &outPath,
                    outPath.count
                )
            }

            guard result == RAC_SUCCESS else { return nil }
            return URL(fileURLWithPath: String(cString: outPath))
        }

        /// Check if a download URL requires extraction.
        /// Uses C++ rac_download_requires_extraction() — convenience wrapper around rac_archive_type_from_path().
        public static func downloadRequiresExtraction(url: URL) -> Bool {
            return url.absoluteString.withCString { urlStr in
                rac_download_requires_extraction(urlStr) == RAC_TRUE
            }
        }

        /// Compute download destination path using C++ rac_download_compute_destination().
        /// Returns the path and whether extraction is needed, or nil on failure.
        public static func computeDownloadDestination(
            modelId: String,
            downloadURL: URL,
            framework: InferenceFramework,
            format: ModelFormat
        ) -> (path: URL, needsExtraction: Bool)? {
            var outPath = [CChar](repeating: 0, count: 4096)
            var needsExtraction: rac_bool_t = RAC_FALSE

            let result = modelId.withCString { mid in
                downloadURL.absoluteString.withCString { urlStr in
                    rac_download_compute_destination(
                        mid,
                        urlStr,
                        framework.toC(),
                        format.toC(),
                        &outPath,
                        outPath.count,
                        &needsExtraction
                    )
                }
            }

            guard result == RAC_SUCCESS else { return nil }
            return (
                path: URL(fileURLWithPath: String(cString: outPath)),
                needsExtraction: needsExtraction == RAC_TRUE
            )
        }

        private var handle: rac_download_manager_handle_t?
        private let logger = SDKLogger(category: "CppBridge.Download")

        /// Active progress callbacks (taskId -> callback)
        private var progressCallbacks: [String: (DownloadProgress) -> Void] = [:]

        private init() {
            var handlePtr: rac_download_manager_handle_t?
            let result = rac_download_manager_create(nil, &handlePtr)
            if result == RAC_SUCCESS {
                self.handle = handlePtr
                logger.debug("Download manager created")
            } else {
                logger.error("Failed to create download manager")
            }
        }

        deinit {
            if let handle = handle {
                rac_download_manager_destroy(handle)
            }
        }

        // MARK: - Download Operations

        /// Start a download task
        /// Returns the task ID for tracking
        public func startDownload(
            modelId: String,
            url: URL,
            destinationPath: URL,
            requiresExtraction: Bool,
            progressHandler: @escaping (DownloadProgress) -> Void
        ) throws -> String {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Download manager not initialized")
            }

            var taskIdPtr: UnsafeMutablePointer<CChar>?

            let result = modelId.withCString { mid in
                url.absoluteString.withCString { urlStr in
                    destinationPath.path.withCString { destPath in
                        rac_download_manager_start(
                            handle,
                            mid,
                            urlStr,
                            destPath,
                            requiresExtraction ? RAC_TRUE : RAC_FALSE,
                            nil,  // Progress callback handled via polling
                            nil,  // Complete callback handled via polling
                            nil,  // User data
                            &taskIdPtr
                        )
                    }
                }
            }

            guard result == RAC_SUCCESS, let taskId = taskIdPtr else {
                throw SDKException.download(.downloadFailed, "Failed to start download")
            }

            let taskIdString = String(cString: taskId)
            free(taskId)

            // Store progress callback
            progressCallbacks[taskIdString] = progressHandler

            logger.info("Started download task: \(taskIdString)")
            return taskIdString
        }

        /// Cancel a download task
        public func cancelDownload(taskId: String) throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Download manager not initialized")
            }

            let result = taskId.withCString { tid in
                rac_download_manager_cancel(handle, tid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException.download(.downloadFailed, "Failed to cancel download")
            }

            progressCallbacks.removeValue(forKey: taskId)
            logger.info("Cancelled download task: \(taskId)")
        }

        /// Pause all downloads
        public func pauseAll() throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Download manager not initialized")
            }

            let result = rac_download_manager_pause_all(handle)
            guard result == RAC_SUCCESS else {
                throw SDKException.download(.downloadFailed, "Failed to pause downloads")
            }

            logger.info("Paused all downloads")
        }

        /// Resume all downloads
        public func resumeAll() throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Download manager not initialized")
            }

            let result = rac_download_manager_resume_all(handle)
            guard result == RAC_SUCCESS else {
                throw SDKException.download(.downloadFailed, "Failed to resume downloads")
            }

            logger.info("Resumed all downloads")
        }

        // MARK: - Progress Tracking

        /// Get progress for a task
        public func getProgress(taskId: String) -> DownloadProgress? {
            guard let handle = handle else { return nil }

            var cProgress = RAC_DOWNLOAD_PROGRESS_DEFAULT
            let result = taskId.withCString { tid in
                rac_download_manager_get_progress(handle, tid, &cProgress)
            }

            guard result == RAC_SUCCESS else { return nil }
            return DownloadProgress(from: cProgress)
        }

        /// Get active task IDs
        public func getActiveTasks() -> [String] {
            guard let handle = handle else { return [] }

            var taskIdsPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0

            let result = rac_download_manager_get_active_tasks(handle, &taskIdsPtr, &count)
            guard result == RAC_SUCCESS, let taskIds = taskIdsPtr else { return [] }
            defer { rac_download_task_ids_free(taskIds, count) }

            var ids: [String] = []
            for i in 0..<count {
                if let tid = taskIds[i] {
                    ids.append(String(cString: tid))
                }
            }

            return ids
        }

        /// Check if download service is healthy
        public func isHealthy() -> Bool {
            guard let handle = handle else { return false }

            var healthy: rac_bool_t = RAC_FALSE
            let result = rac_download_manager_is_healthy(handle, &healthy)

            return result == RAC_SUCCESS && healthy == RAC_TRUE
        }

        // MARK: - Proto Download Workflow

        public func plan(_ request: RADownloadPlanRequest) -> RADownloadPlanResult {
            do {
                return try invokeProto(
                    request,
                    symbol: DownloadProtoABI.plan,
                    responseType: RADownloadPlanResult.self
                )
            } catch {
                var result = RADownloadPlanResult()
                result.canStart = false
                result.modelID = request.modelID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func start(_ request: RADownloadStartRequest) -> RADownloadStartResult {
            do {
                return try invokeProto(
                    request,
                    symbol: DownloadProtoABI.start,
                    responseType: RADownloadStartResult.self
                )
            } catch {
                var result = RADownloadStartResult()
                result.accepted = false
                result.modelID = request.modelID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func cancel(_ request: RADownloadCancelRequest) -> RADownloadCancelResult {
            do {
                return try invokeProto(
                    request,
                    symbol: DownloadProtoABI.cancel,
                    responseType: RADownloadCancelResult.self
                )
            } catch {
                var result = RADownloadCancelResult()
                result.success = false
                result.modelID = request.modelID
                result.taskID = request.taskID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func resume(_ request: RADownloadResumeRequest) -> RADownloadResumeResult {
            do {
                return try invokeProto(
                    request,
                    symbol: DownloadProtoABI.resume,
                    responseType: RADownloadResumeResult.self
                )
            } catch {
                var result = RADownloadResumeResult()
                result.accepted = false
                result.modelID = request.modelID
                result.taskID = request.taskID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func pollProgress(_ request: RADownloadSubscribeRequest) -> RADownloadProgress {
            do {
                return try invokeProto(
                    request,
                    symbol: DownloadProtoABI.pollProgress,
                    responseType: RADownloadProgress.self
                )
            } catch {
                var progress = RADownloadProgress()
                progress.modelID = request.modelID
                progress.taskID = request.taskID
                progress.state = .failed
                progress.errorMessage = String(describing: error)
                return progress
            }
        }

        public nonisolated func progressEvents() -> AsyncStream<RADownloadProgress> {
            AsyncStream { continuation in
                guard let setProgressCallback = DownloadProtoABI.setProgressCallback else {
                    continuation.finish()
                    return
                }

                let box = DownloadProtoProgressBox(continuation: continuation)
                let retained = Unmanaged.passRetained(box)
                let opaque = retained.toOpaque()
                let status = setProgressCallback(downloadProtoProgressCallback, opaque)

                guard status == RAC_SUCCESS else {
                    retained.release()
                    continuation.finish()
                    return
                }

                continuation.onTermination = { _ in
                    _ = setProgressCallback(nil, nil)
                    Unmanaged<DownloadProtoProgressBox>.fromOpaque(opaque).release()
                }
            }
        }

        // MARK: - Progress Updates (called by platform HTTP layer)

        /// Update download progress (called by Alamofire/HTTP layer)
        public func updateProgress(taskId: String, bytesDownloaded: Int64, totalBytes: Int64) {
            guard let handle = handle else { return }

            _ = taskId.withCString { tid in
                rac_download_manager_update_progress(handle, tid, bytesDownloaded, totalBytes)
            }

            // Notify callback
            if let progress = getProgress(taskId: taskId),
               let callback = progressCallbacks[taskId] {
                callback(progress)
            }
        }

        private func invokeProto<Request: Message, Response: Message>(
            _ request: Request,
            symbol: DownloadProtoABI.ProtoFunction?,
            responseType: Response.Type
        ) throws -> Response {
            guard let symbol, NativeProtoABI.canReceiveProtoBuffer else {
                throw SDKException.general(.notSupported, NativeProtoABI.unavailableMessage)
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }

            let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(bytes, size, &outBuffer)
            }
            guard status == RAC_SUCCESS else {
                throw SDKException.general(.processingFailed, "Download proto request failed: \(status)")
            }
            return try NativeProtoABI.decode(responseType, from: outBuffer)
        }

        /// Mark download as complete (called by Alamofire/HTTP layer)
        public func markComplete(taskId: String, downloadedPath: URL) {
            guard let handle = handle else { return }

            _ = taskId.withCString { tid in
                downloadedPath.path.withCString { path in
                    rac_download_manager_mark_complete(handle, tid, path)
                }
            }

            // Notify final progress
            if let progress = getProgress(taskId: taskId),
               let callback = progressCallbacks[taskId] {
                callback(progress)
            }

            progressCallbacks.removeValue(forKey: taskId)
            logger.info("Download completed: \(taskId)")
        }

        /// Mark download as failed (called by Alamofire/HTTP layer)
        public func markFailed(taskId: String, error: SDKException) {
            guard let handle = handle else { return }

            let errorCode = RAC_ERROR_DOWNLOAD_FAILED  // Map to appropriate error
            let errorMessage = error.localizedDescription

            _ = taskId.withCString { tid in
                errorMessage.withCString { msg in
                    rac_download_manager_mark_failed(handle, tid, errorCode, msg)
                }
            }

            // Notify final progress
            if let progress = getProgress(taskId: taskId),
               let callback = progressCallbacks[taskId] {
                callback(progress)
            }

            progressCallbacks.removeValue(forKey: taskId)
            logger.error("Download failed: \(taskId) - \(errorMessage)")
        }
    }
}
