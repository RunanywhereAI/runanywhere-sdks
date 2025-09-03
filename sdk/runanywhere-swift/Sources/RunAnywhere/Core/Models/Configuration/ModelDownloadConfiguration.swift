import Foundation

// MARK: - Download Policy

/// Download policy for models
public enum DownloadPolicy: String, Codable, Sendable {
    case automatic = "automatic"      // Download automatically if needed
    case wifiOnly = "wifi_only"       // Only download on WiFi
    case manual = "manual"             // Require user confirmation
    case never = "never"               // Don't download, fail if not available
}

// MARK: - Model Download Configuration

/// Simple configuration for model downloads
public struct ModelDownloadConfiguration: Codable, Sendable {

    /// Download policy
    public var policy: DownloadPolicy

    /// Maximum concurrent downloads
    public var maxConcurrentDownloads: Int

    /// Number of retry attempts
    public var retryCount: Int

    /// Download timeout in seconds
    public var timeout: TimeInterval

    /// Enable background downloads
    public var enableBackgroundDownloads: Bool

    public init(
        policy: DownloadPolicy = .automatic,
        maxConcurrentDownloads: Int = 3,
        retryCount: Int = 3,
        timeout: TimeInterval = 300.0,
        enableBackgroundDownloads: Bool = false
    ) {
        self.policy = policy
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.retryCount = retryCount
        self.timeout = timeout
        self.enableBackgroundDownloads = enableBackgroundDownloads
    }
}

// MARK: - Simple Helper

extension ModelDownloadConfiguration {

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
