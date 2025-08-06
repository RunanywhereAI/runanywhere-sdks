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

    // MARK: - Database Constants

    /// Database configuration
    public enum DatabaseDefaults {
        /// Database file name
        public static let databaseFileName = "runanywhere.db"

        /// Default SDK version for database records
        public static let sdkVersion = "1.0.0"

        /// Default model version
        public static let modelVersion = "1.0"

        /// Default base URL for API
        public static let apiBaseURL = "https://api.runanywhere.ai"
    }

    // MARK: - Telemetry Constants

    /// Telemetry configuration
    public enum TelemetryDefaults {
        /// Batch size for telemetry sync
        public static let batchSize = 50

        /// Telemetry consent levels
        public static let consentNone = "none"
        public static let consentAnonymous = "anonymous"
        public static let consentDetailed = "detailed"
    }

    // MARK: - Model Constants

    /// Model metadata defaults
    public enum ModelDefaults {
        /// Default context length for models
        public static let defaultContextLength = 4096

        /// Default execution target
        public static let defaultExecutionTarget = "device"

        /// Default model cache size
        public static let defaultModelCacheSize = 5

        /// Default max memory usage in MB
        public static let defaultMaxMemoryUsageMB = 1024

        /// Memory buffer percentage for recommended memory (25%)
        public static let recommendedMemoryBufferPercentage = 0.25
    }

    // MARK: - Privacy Constants

    /// Privacy mode defaults
    public enum PrivacyDefaults {
        /// Default privacy mode
        public static let defaultPrivacyMode = "standard"
    }

    // MARK: - Analytics Constants

    /// Analytics configuration defaults
    public enum AnalyticsDefaults {
        /// Analytics levels
        public static let levelBasic = "basic"
        public static let levelDetailed = "detailed"
        public static let levelDebug = "debug"

        /// Default analytics level
        public static let defaultLevel = levelBasic
    }

    // MARK: - Storage Constants

    /// Storage configuration defaults
    public enum StorageDefaults {
        /// Default max cache size in MB
        public static let defaultMaxCacheSizeMB = 2048

        /// Default cleanup threshold percentage
        public static let defaultCleanupThresholdPercentage = 90

        /// Default model retention days
        public static let defaultModelRetentionDays = 30
    }

    // MARK: - Routing Constants

    /// Routing policy defaults
    public enum RoutingDefaults {
        /// Default on-device threshold (0.0 to 1.0)
        public static let defaultOnDeviceThreshold = 0.8
    }

    // MARK: - Execution Constants

    /// Execution target constants
    public enum ExecutionTargets {
        /// On-device execution
        public static let onDevice = "onDevice"

        /// Cloud execution
        public static let cloud = "cloud"
    }

    // MARK: - Session Constants

    /// Session type constants
    public enum SessionTypes {
        /// Chat session
        public static let chat = "chat"

        /// Completion session
        public static let completion = "completion"
    }

    // MARK: - Platform Constants

    /// Platform constants
    public enum PlatformDefaults {
        /// Default supported platforms
        public static let defaultSupportedPlatforms = ["iOS", "macOS"]
    }

    // MARK: - Routing Policies
    // Note: RoutingPolicy enum has been moved to Public/Configuration/RoutingPolicy.swift
}
