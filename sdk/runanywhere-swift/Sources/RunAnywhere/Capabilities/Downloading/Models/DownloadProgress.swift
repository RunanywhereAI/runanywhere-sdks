import Foundation

/// Download progress information
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let state: DownloadState
    public let estimatedTimeRemaining: TimeInterval?

    public var percentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }

    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        state: DownloadState,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.state = state
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}
