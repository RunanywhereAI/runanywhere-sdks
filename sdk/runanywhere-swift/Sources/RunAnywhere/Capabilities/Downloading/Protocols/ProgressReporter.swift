import Foundation

/// Protocol for reporting download progress
public protocol ProgressReporter {
    /// Report download progress
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - progress: The current download progress
    func reportProgress(taskId: String, progress: DownloadProgress) async
}
