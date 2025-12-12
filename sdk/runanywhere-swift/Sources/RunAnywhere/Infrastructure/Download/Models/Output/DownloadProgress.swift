import Foundation

/// Download progress information
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let state: DownloadState
    public let estimatedTimeRemaining: TimeInterval?
    public let speed: Double? // bytes per second
    public let percentage: Double

    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        percentage: Double,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        state: DownloadState
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.percentage = percentage
        self.speed = speed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.state = state
    }

    // Convenience init without percentage (calculates it)
    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        state: DownloadState,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.state = state
        self.speed = speed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.percentage = totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0
    }
}
