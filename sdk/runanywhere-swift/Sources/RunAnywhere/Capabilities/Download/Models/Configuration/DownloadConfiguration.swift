import Foundation

// MARK: - Download Policy

/// Download policy for models
public enum DownloadPolicy: String, Codable, Sendable {
    case automatic = "automatic"      // Download automatically if needed
    case wifiOnly = "wifi_only"       // Only download on WiFi
    case manual = "manual"             // Require user confirmation
    case never = "never"               // Don't download, fail if not available
}

// MARK: - Download Configuration

/// Configuration for download behavior
public struct DownloadConfiguration: Codable, Sendable {
    /// Download policy
    public var policy: DownloadPolicy

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
        policy: DownloadPolicy = .automatic,
        maxConcurrentDownloads: Int = 3,
        retryCount: Int = 3,
        retryDelay: TimeInterval = 2.0,
        timeout: TimeInterval = 300.0,
        chunkSize: Int = 1024 * 1024, // 1MB chunks
        resumeOnFailure: Bool = true,
        verifyChecksum: Bool = true,
        enableBackgroundDownloads: Bool = false
    ) {
        self.policy = policy
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

// MARK: - Helper Methods

extension DownloadConfiguration {
    /// Check if download is allowed
    public func shouldAllowDownload(isWiFi: Bool = false, userConfirmed: Bool = false) -> Bool {
        switch policy {
        case .automatic:
            return true
        case .wifiOnly:
            return isWiFi
        case .manual:
            return userConfirmed
        case .never:
            return false
        }
    }
}
