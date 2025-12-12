import Foundation

/// Download and network configuration constants
public enum DownloadConstants {

    // MARK: - Timeout Configuration

    /// Default API timeout in seconds
    public static let defaultAPITimeout: TimeInterval = 60

    /// Default download timeout in seconds
    public static let defaultDownloadTimeout: TimeInterval = 300

    // MARK: - Retry Configuration

    /// Maximum retry attempts
    public static let maxRetryAttempts = 3

    /// Retry delay in seconds
    public static let retryDelay: TimeInterval = 1.0

    /// Default batch size for operations
    public static let defaultBatchSize = 32
}
