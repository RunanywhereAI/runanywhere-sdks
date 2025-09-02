//
//  LoggingManager.swift
//  RunAnywhere SDK
//
//  Central logging coordination service
//
//  Current Implementation:
//  - Uses Pulse for local debugging and development
//  - Remote logging temporarily disabled pending service selection
//
//  Remote Logging Strategy:
//  - Recommended: Sentry for production error tracking
//  - Alternative: DataDog for enterprise integration
//  - See RemoteLoggingService.swift for detailed recommendations
//

import Foundation
import Pulse

/// Centralized logging manager for the SDK
/// Uses Pulse for local logging and prepares for remote service integration
public class LoggingManager {

    // MARK: - Singleton

    public static let shared = LoggingManager()

    // MARK: - Properties

    /// Current logging configuration
    public private(set) var configuration = LoggingConfiguration()

    /// SDK Environment
    private let environment: SDKEnvironment

    /// Pulse logger for local debugging and development
    private let pulseLogger = LoggerStore.shared

    /// Lock for thread-safe configuration updates
    private let configLock = NSLock()

    /// Logger for internal use
    private let logger = SDKLogger(category: "LoggingManager")

    // MARK: - Initialization

    private init() {
        // Get environment from RunAnywhere initialization
        self.environment = RunAnywhere._currentEnvironment ?? .production

        // Apply environment-based configuration
        applyEnvironmentConfiguration()
    }

    // MARK: - Public Methods

    /// Update logging configuration
    public func configure(_ config: LoggingConfiguration) {
        configLock.lock()
        defer { configLock.unlock() }

        self.configuration = config

        // Remote logging configuration will be handled by external service
        // when implemented (e.g., Sentry, DataDog, etc.)
    }

    /// Configure SDK logging endpoint (for SDK team debugging)
    public func configureSDKLogging(endpoint: URL?, enabled: Bool = true) {
        configLock.lock()
        defer { configLock.unlock() }

        configuration.remoteEndpoint = endpoint
        configuration.enableRemoteLogging = enabled && endpoint != nil

        // This will be replaced with external service configuration
        // e.g., Sentry.configure(dsn: endpoint)

        // Log configuration change
        let entry = LogEntry(
            timestamp: Date(),
            level: .info,
            category: "LoggingManager",
            message: "SDK logging configured: \(enabled ? "enabled" : "disabled")",
            metadata: nil,
            deviceInfo: nil
        )
        logToPulse(entry, isSensitive: false)
    }

    /// Log a message with the specified level and metadata
    internal func log(level: LogLevel, category: String, message: String, metadata: [String: Any]? = nil) {
        // Check against SDK configuration minimum log level
        guard level >= configuration.minLogLevel else { return }

        // Check if this contains sensitive data
        let isSensitive = checkIfSensitive(metadata: metadata)

        // Create log entry
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            deviceInfo: configuration.includeDeviceMetadata ? DeviceInfo.current : nil
        )

        // Local logging with Pulse
        if configuration.enableLocalLogging {
            logToPulse(entry, isSensitive: isSensitive)
        }

        // Remote logging - ONLY if not sensitive
        // TODO: Integrate with external logging service (Sentry/DataDog/etc)
        if configuration.enableRemoteLogging && !isSensitive {
            // Will be implemented with external service
            // e.g., Sentry.capture(event: entry)
        }
    }

    /// Force flush all pending logs
    public func flush() {
        // Will flush external service when implemented
        // e.g., Sentry.flush()
    }

    // MARK: - Private Methods

    private func logToPulse(_ entry: LogEntry, isSensitive: Bool) {
        var pulseMetadata: [String: LoggerStore.MetadataValue] = [:]

        // Add category
        pulseMetadata["category"] = .string(entry.category)

        // Convert metadata to Pulse format
        if let metadata = entry.metadata {
            for (key, value) in metadata {
                // Skip internal sensitive data markers
                if key.hasPrefix("__") { continue }

                pulseMetadata[key] = convertToMetadataValue(value)
            }
        }

        // Mark if sensitive
        if isSensitive {
            pulseMetadata["sensitive"] = .string("true")
        }

        // Convert LogLevel to Pulse level
        let pulseLevel = convertToPulseLevel(entry.level)

        // Log to Pulse
        pulseLogger.storeMessage(
            label: entry.category,
            level: pulseLevel,
            message: entry.message,
            metadata: pulseMetadata.isEmpty ? nil : pulseMetadata
        )
    }

    private func convertToPulseLevel(_ level: LogLevel) -> LoggerStore.Level {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fault: return .critical
        }
    }

    private func convertToMetadataValue(_ value: Any) -> LoggerStore.MetadataValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .string(String(int))
        case let double as Double:
            return .string(String(double))
        case let bool as Bool:
            return .string(String(bool))
        default:
            return .string(String(describing: value))
        }
    }

    private func checkIfSensitive(metadata: [String: Any]?) -> Bool {
        guard let metadata = metadata else { return false }

        // Check for sensitive data markers
        if let _ = metadata[LogMetadataKeys.sensitiveDataPolicy] {
            return true
        }

        if let _ = metadata[LogMetadataKeys.sensitiveDataCategory] {
            return true
        }

        return false
    }

    private func sanitizeForRemote(_ entry: LogEntry) -> LogEntry {
        // Remove any sensitive metadata
        var sanitizedMetadata = entry.metadata ?? [:]

        // Remove sensitive markers and content
        sanitizedMetadata.removeValue(forKey: LogMetadataKeys.sensitiveDataPolicy)
        sanitizedMetadata.removeValue(forKey: LogMetadataKeys.sensitiveDataCategory)
        sanitizedMetadata.removeValue(forKey: LogMetadataKeys.isUserContent)
        sanitizedMetadata.removeValue(forKey: LogMetadataKeys.containsPII)

        // Create sanitized entry
        return LogEntry(
            timestamp: entry.timestamp,
            level: entry.level,
            category: entry.category,
            message: entry.message,
            metadata: sanitizedMetadata,
            deviceInfo: entry.deviceInfo
        )
    }

    private func applyEnvironmentConfiguration() {
        // Update SDK configuration based on environment
        var config = configuration

        // Set defaults based on environment
        switch environment {
        case .development:
            config.enableLocalLogging = true
            config.enableRemoteLogging = false
            config.minLogLevel = .debug
            config.includeDeviceMetadata = false
        case .staging:
            config.enableLocalLogging = false
            config.enableRemoteLogging = true
            config.minLogLevel = .info
            config.includeDeviceMetadata = true
        case .production:
            config.enableLocalLogging = false
            config.enableRemoteLogging = true
            config.minLogLevel = .warning
            config.includeDeviceMetadata = true
        }

        // Update configuration
        self.configuration = config

        // Configure Pulse
        configurePulse()

        // Log current environment for debugging
        if environment == .development {
            let entry = LogEntry(
                timestamp: Date(),
                level: .info,
                category: "LoggingManager",
                message: "🚀 Running in \(environment.rawValue) environment - Remote: \(config.enableRemoteLogging), MinLevel: \(config.minLogLevel)",
                metadata: nil,
                deviceInfo: nil
            )
            logToPulse(entry, isSensitive: false)
        }
    }

    private func configurePulse() {
        // Enable automatic network logging
        URLSessionProxyDelegate.enableAutomaticRegistration()

        // Pulse configuration is done at the LoggerStore level
        // Network logging is enabled by default when using URLSessionProxyDelegate
    }
}
