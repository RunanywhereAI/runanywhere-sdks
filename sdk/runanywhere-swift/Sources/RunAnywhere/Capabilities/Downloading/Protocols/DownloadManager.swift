import Foundation

/// Protocol for download management operations
public protocol DownloadManager {
    /// Download a model
    /// - Parameter model: The model to download
    /// - Returns: A download task tracking the download
    /// - Throws: An error if download setup fails
    func downloadModel(_ model: ModelInfo) async throws -> DownloadTask

    /// Cancel a download
    /// - Parameter taskId: The ID of the task to cancel
    func cancelDownload(taskId: String)

    /// Get all active downloads
    /// - Returns: Array of active download tasks
    func activeDownloads() -> [DownloadTask]
}
