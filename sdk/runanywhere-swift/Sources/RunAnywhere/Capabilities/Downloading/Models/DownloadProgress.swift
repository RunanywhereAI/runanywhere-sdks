import Foundation

/// Download progress information
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentComplete: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let downloadSpeed: Double // bytes per second
    public let status: DownloadStatus

    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        percentComplete: Double,
        estimatedTimeRemaining: TimeInterval? = nil,
        downloadSpeed: Double = 0,
        status: DownloadStatus = .downloading
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.percentComplete = percentComplete
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.downloadSpeed = downloadSpeed
        self.status = status
    }
}
