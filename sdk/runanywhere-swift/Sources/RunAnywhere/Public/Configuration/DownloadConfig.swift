import Foundation

/// Download configuration
public struct DownloadConfig {
    /// Maximum concurrent downloads
    public let maxConcurrentDownloads: Int

    /// Number of retry attempts
    public let retryAttempts: Int

    /// Custom cache directory
    public let cacheDirectory: URL?

    /// Download timeout in seconds
    public let timeoutInterval: TimeInterval

    public init(
        maxConcurrentDownloads: Int = 2,
        retryAttempts: Int = 3,
        cacheDirectory: URL? = nil,
        timeoutInterval: TimeInterval = 300
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.retryAttempts = retryAttempts
        self.cacheDirectory = cacheDirectory
        self.timeoutInterval = timeoutInterval
    }
}
