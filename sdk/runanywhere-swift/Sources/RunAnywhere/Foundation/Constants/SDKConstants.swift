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

    // MARK: - Configuration Defaults

    /// Default configuration values
    public enum ConfigurationDefaults {
        // Generation settings
        public static let temperature: Double = 0.7
        public static let maxTokens: Int = 256
        public static let topP: Double = 0.95
        public static let topK: Int = 40

        // SDK configuration - FORCE LOCAL ONLY
        public static let cloudRoutingEnabled: Bool = false  // Disable cloud routing completely
        public static let privacyModeEnabled: Bool = true
        public static let routingPolicy = RoutingPolicy.deviceOnly  // Force on-device only
        public static let allowUserOverride: Bool = false  // Don't allow override to cloud

        // Analytics configuration - hardcoded to be fully enabled
        public static let analyticsEnabled: Bool = true
        public static let analyticsLevel = AnalyticsLevel.verbose  // Changed to verbose for complete analytics
        public static let enableLiveMetrics: Bool = true   // Enable live metrics for better real-time tracking

        // Configuration ID
        public static let configurationId: String = "default"
    }

    // MARK: - Routing Policies
    // Note: RoutingPolicy enum has been moved to Public/Configuration/RoutingPolicy.swift
}
