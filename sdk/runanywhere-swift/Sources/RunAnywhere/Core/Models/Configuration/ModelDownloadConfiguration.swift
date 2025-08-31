import Foundation

/// Configuration for model downloads
public struct ModelDownloadConfiguration: Codable, Sendable {
    /// Maximum concurrent downloads
    public var maxConcurrentDownloads: Int

    /// Number of retry attempts
    public var retryCount: Int

    /// Retry delay in seconds
    public var retryDelay: TimeInterval

    /// Download timeout in seconds
    public var timeout: TimeInterval

    /// Chunk size for downloads
    public var chunkSize: Int

    /// Resume downloads on failure
    public var resumeOnFailure: Bool

    /// Verify checksums after download
    public var verifyChecksum: Bool

    /// Custom cache directory path (relative to app container)
    public var cacheDirectoryPath: String?

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
        cacheDirectoryPath: String? = nil,
        enableBackgroundDownloads: Bool = false
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.retryCount = retryCount
        self.retryDelay = retryDelay
        self.timeout = timeout
        self.chunkSize = chunkSize
        self.resumeOnFailure = resumeOnFailure
        self.verifyChecksum = verifyChecksum
        self.cacheDirectoryPath = cacheDirectoryPath
        self.enableBackgroundDownloads = enableBackgroundDownloads
    }
}
