//
//  CppBridge+Download.swift
//  RunAnywhere SDK
//
//  Download manager bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Download Bridge

extension CppBridge {

    /// Download manager bridge
    /// Wraps C++ rac_download.h functions for download orchestration
    public actor Download {

        /// Shared download manager instance
        public static let shared = Download()

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
                throw SDKError.general(.initializationFailed, "Download manager not initialized")
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
                throw SDKError.download(.downloadFailed, "Failed to start download")
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
                throw SDKError.general(.initializationFailed, "Download manager not initialized")
            }

            let result = taskId.withCString { tid in
                rac_download_manager_cancel(handle, tid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.download(.downloadFailed, "Failed to cancel download")
            }

            progressCallbacks.removeValue(forKey: taskId)
            logger.info("Cancelled download task: \(taskId)")
        }

        /// Pause all downloads
        public func pauseAll() throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Download manager not initialized")
            }

            let result = rac_download_manager_pause_all(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.download(.downloadFailed, "Failed to pause downloads")
            }

            logger.info("Paused all downloads")
        }

        /// Resume all downloads
        public func resumeAll() throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Download manager not initialized")
            }

            let result = rac_download_manager_resume_all(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.download(.downloadFailed, "Failed to resume downloads")
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
        public func markFailed(taskId: String, error: SDKError) {
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
