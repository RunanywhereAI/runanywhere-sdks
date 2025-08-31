import Foundation

/// Environment configuration for the SDK
public struct EnvironmentConfiguration {
    /// The current environment type
    public enum Environment: String {
        case debug
        case staging
        case production

        /// Check if we're in a debug environment
        public var isDebug: Bool {
            self == .debug
        }
    }

    /// Logging configuration
    public struct LoggingConfig {
        /// Enable console logging
        public let enableConsoleLogging: Bool

        /// Enable file logging
        public let enableFileLogging: Bool

        /// Enable remote logging
        public let enableRemoteLogging: Bool

        /// Minimum log level to output
        public let minimumLogLevel: LogLevel

        /// Enable sensitive data logging (only in debug)
        public let enableSensitiveDataLogging: Bool

        /// Max log file size in MB
        public let maxLogFileSizeMB: Int

        /// Log retention days
        public let logRetentionDays: Int
    }

    /// API configuration
    public struct APIConfig {
        /// Base URL for API
        public let baseURL: String

        /// API timeout in seconds
        public let timeoutSeconds: TimeInterval

        /// Enable request/response logging
        public let enableRequestLogging: Bool
    }

    // MARK: - Properties

    /// Current environment
    public let environment: Environment

    /// Logging configuration
    public let logging: LoggingConfig

    /// API configuration
    public let api: APIConfig

    /// Enable performance monitoring
    public let enablePerformanceMonitoring: Bool

    /// Enable crash reporting
    public let enableCrashReporting: Bool

    // MARK: - Singleton

    /// Shared instance - automatically detects environment
    public static let shared: EnvironmentConfiguration = {
        // Detect environment based on build configuration
        #if DEBUG
        return .debug
        #else
        // Check if we have a staging flag
        if ProcessInfo.processInfo.environment["RUNANYWHERE_STAGING"] != nil {
            return .staging
        }
        return .production
        #endif
    }()

    // MARK: - Predefined Configurations

    /// Debug configuration
    public static let debug = EnvironmentConfiguration(
        environment: .debug,
        logging: LoggingConfig(
            enableConsoleLogging: true,
            enableFileLogging: true,
            enableRemoteLogging: false,
            minimumLogLevel: .debug,
            enableSensitiveDataLogging: true,
            maxLogFileSizeMB: 50,
            logRetentionDays: 7
        ),
        api: APIConfig(
            baseURL: RunAnywhereConstants.apiURLs.development,
            timeoutSeconds: 30,
            enableRequestLogging: true
        ),
        enablePerformanceMonitoring: true,
        enableCrashReporting: false
    )

    /// Staging configuration
    public static let staging = EnvironmentConfiguration(
        environment: .staging,
        logging: LoggingConfig(
            enableConsoleLogging: false,
            enableFileLogging: true,
            enableRemoteLogging: true,
            minimumLogLevel: .info,
            enableSensitiveDataLogging: false,
            maxLogFileSizeMB: 20,
            logRetentionDays: 30
        ),
        api: APIConfig(
            baseURL: RunAnywhereConstants.apiURLs.staging,
            timeoutSeconds: 20,
            enableRequestLogging: false
        ),
        enablePerformanceMonitoring: true,
        enableCrashReporting: true
    )

    /// Production configuration
    public static let production = EnvironmentConfiguration(
        environment: .production,
        logging: LoggingConfig(
            enableConsoleLogging: false,
            enableFileLogging: true,
            enableRemoteLogging: true,
            minimumLogLevel: .warning,
            enableSensitiveDataLogging: false,
            maxLogFileSizeMB: 10,
            logRetentionDays: 90
        ),
        api: APIConfig(
            baseURL: RunAnywhereConstants.apiURLs.production,
            timeoutSeconds: 15,
            enableRequestLogging: false
        ),
        enablePerformanceMonitoring: false,
        enableCrashReporting: true
    )

    // MARK: - Custom Configuration Support

    /// Load configuration from a plist file in the app bundle
    public static func loadFromPlist(named name: String = "RunAnywhereConfig") -> EnvironmentConfiguration? {
        guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }

        // Parse configuration from plist
        let environmentString = dict["environment"] as? String ?? "production"
        let environment = Environment(rawValue: environmentString) ?? .production

        // Parse logging config
        let loggingDict = dict["logging"] as? [String: Any] ?? [:]
        let logging = LoggingConfig(
            enableConsoleLogging: loggingDict["enableConsoleLogging"] as? Bool ?? false,
            enableFileLogging: loggingDict["enableFileLogging"] as? Bool ?? true,
            enableRemoteLogging: loggingDict["enableRemoteLogging"] as? Bool ?? false,
            minimumLogLevel: LogLevel(rawValue: loggingDict["minimumLogLevel"] as? String ?? "info") ?? .info,
            enableSensitiveDataLogging: loggingDict["enableSensitiveDataLogging"] as? Bool ?? false,
            maxLogFileSizeMB: loggingDict["maxLogFileSizeMB"] as? Int ?? 10,
            logRetentionDays: loggingDict["logRetentionDays"] as? Int ?? 30
        )

        // Parse API config
        let apiDict = dict["api"] as? [String: Any] ?? [:]
        let api = APIConfig(
            baseURL: apiDict["baseURL"] as? String ?? RunAnywhereConstants.apiURLs.production,
            timeoutSeconds: apiDict["timeoutSeconds"] as? TimeInterval ?? 15,
            enableRequestLogging: apiDict["enableRequestLogging"] as? Bool ?? false
        )

        return EnvironmentConfiguration(
            environment: environment,
            logging: logging,
            api: api,
            enablePerformanceMonitoring: dict["enablePerformanceMonitoring"] as? Bool ?? false,
            enableCrashReporting: dict["enableCrashReporting"] as? Bool ?? true
        )
    }
}

// MARK: - Environment Detection Helpers

public extension EnvironmentConfiguration {
    /// Check if running in Xcode
    static var isRunningInXcode: Bool {
        ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }

    /// Check if running in TestFlight
    static var isRunningInTestFlight: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }

    /// Check if running unit tests
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Check if running UI tests
    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    /// Override configuration for testing
    private static var testOverride: EnvironmentConfiguration?

    /// Set a test configuration (only works in DEBUG)
    static func setTestConfiguration(_ config: EnvironmentConfiguration?) {
        #if DEBUG
        testOverride = config
        #endif
    }

    /// Get the current active configuration
    static var current: EnvironmentConfiguration {
        #if DEBUG
        if let override = testOverride {
            return override
        }
        #endif

        // Try to load from plist first
        if let plistConfig = loadFromPlist() {
            return plistConfig
        }

        // Fall back to shared instance
        return shared
    }
}

// MARK: - LogLevel Extension

extension LogLevel {
    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "warning": self = .warning
        case "error": self = .error
        case "fault": self = .fault
        default: return nil
        }
    }
}
