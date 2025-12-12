import Foundation

/// Storage and file management configuration constants
public enum StorageConstants {

    // MARK: - Directory Names

    /// Model directory name
    public static let modelDirectoryName = "RunAnywhereModels"

    /// Cache directory name
    public static let cacheDirectoryName = "RunAnywhereCache"

    /// Temporary directory name
    public static let tempDirectoryName = "RunAnywhereTmp"

    // MARK: - Cache Configuration

    /// Cache size limit in bytes (100 MB)
    public static let cacheSizeLimit: Int64 = 100 * 1024 * 1024

    /// Default max cache size in MB
    public static let defaultMaxCacheSizeMB = 2048

    /// Default cleanup threshold percentage
    public static let defaultCleanupThresholdPercentage = 90

    /// Default model retention days
    public static let defaultModelRetentionDays = 30
}
