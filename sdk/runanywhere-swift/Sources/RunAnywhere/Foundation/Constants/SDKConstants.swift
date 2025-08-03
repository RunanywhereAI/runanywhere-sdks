import Foundation

/// SDK-wide constants
public enum SDKConstants {
    /// SDK version
    public static let version = "1.0.0"

    /// SDK name
    public static let name = "RunAnywhere SDK"

    /// User agent string
    public static let userAgent = "\(name)/\(version) (Swift)"

    /// Default API timeout in seconds
    public static let defaultAPITimeout: TimeInterval = 60

    /// Default download timeout in seconds
    public static let defaultDownloadTimeout: TimeInterval = 300

    /// Maximum retry attempts
    public static let maxRetryAttempts = 3

    /// Retry delay in seconds
    public static let retryDelay: TimeInterval = 1.0

    /// Memory warning threshold (percentage)
    public static let memoryWarningThreshold: Float = 0.8

    /// Memory critical threshold (percentage)
    public static let memoryCriticalThreshold: Float = 0.9

    /// Cache size limit in bytes (100 MB)
    public static let cacheSizeLimit: Int64 = 100 * 1024 * 1024

    /// Default batch size for operations
    public static let defaultBatchSize = 32

    /// Minimum log level in production
    public static let productionLogLevel = "error"

    /// Model directory name
    public static let modelDirectoryName = "RunAnywhereModels"

    /// Cache directory name
    public static let cacheDirectoryName = "RunAnywhereCache"

    /// Temporary directory name
    public static let tempDirectoryName = "RunAnywhereTmp"
}
