import Foundation

// MARK: - Download Configuration

/// Configuration for download behavior
public struct DownloadConfiguration: Codable, Sendable {
    public var maxConcurrentDownloads: Int
    public var retryCount: Int
    public var retryDelay: TimeInterval
    public var timeout: TimeInterval
    public var chunkSize: Int
    public var resumeOnFailure: Bool
    public var verifyChecksum: Bool

    /// Enable background downloads
    public var enableBackgroundDownloads: Bool

    public init(
        maxConcurrentDownloads: Int = 3,
        retryCount: Int = 3,
        retryDelay: TimeInterval = 2.0,
        timeout: TimeInterval = 300.0,
        chunkSize: Int = 1024 * 1024, // 1MB chunks
        resumeOnFailure: Bool = true,
        verifyChecksum: Bool = true,
        enableBackgroundDownloads: Bool = false
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.retryCount = retryCount
        self.retryDelay = retryDelay
        self.timeout = timeout
        self.chunkSize = chunkSize
        self.resumeOnFailure = resumeOnFailure
        self.verifyChecksum = verifyChecksum
        self.enableBackgroundDownloads = enableBackgroundDownloads
    }
}
