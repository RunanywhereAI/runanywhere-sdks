//
//  LoggingManager.swift
//  RunAnywhere SDK
//
//  Central logging coordination service
//

import Foundation
import Pulse

/// Centralized logging manager for the SDK
public class LoggingManager {

    // MARK: - Singleton

    public static let shared = LoggingManager()

    // MARK: - Properties

    /// Current logging configuration
    public private(set) var configuration = LoggingConfiguration()

    /// Environment configuration
    private let envConfig = EnvironmentConfiguration.current

    /// Pulse logger for local debugging
    private let pulseLogger = LoggerStore.shared

    /// Remote logger for telemetry
    private let remoteLogger = RemoteLogger()

    /// Log batcher for efficient remote submission
    private var logBatcher: LogBatcher?

    /// Lock for thread-safe configuration updates
    private let configLock = NSLock()

    // MARK: - Initialization

    private init() {
        // Apply environment-based configuration
        applyEnvironmentConfiguration()
        setupBatcher()
    }

    // MARK: - Public Methods

    /// Update logging configuration
    public func configure(_ config: LoggingConfiguration) {
        configLock.lock()
        defer { configLock.unlock() }

        self.configuration = config

        if config.enableRemoteLogging {
            setupBatcher()
            logBatcher?.updateConfiguration(config)
        } else {
            logBatcher = nil
        }
    }

    /// Configure SDK logging endpoint (for SDK team debugging)
    public func configureSDKLogging(endpoint: URL?, enabled: Bool = true) {
        configLock.lock()
        defer { configLock.unlock() }

        configuration.remoteEndpoint = endpoint
        configuration.enableRemoteLogging = enabled && endpoint != nil

        if configuration.enableRemoteLogging {
            setupBatcher()
        } else {
            logBatcher = nil
        }

        logger.info("SDK logging configured: \(enabled ? "enabled" : "disabled")")
    }

    /// Log a message with the specified level and metadata
    internal func log(level: LogLevel, category: String, message: String, metadata: [String: Any]? = nil) {
        // Check against environment minimum log level first
        guard level >= envConfig.logging.minimumLogLevel else { return }

        // Then check against SDK configuration
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
        if configuration.enableRemoteLogging && envConfig.logging.enableRemoteLogging && !isSensitive {
            let sanitizedEntry = sanitizeForRemote(entry)
            logBatcher?.add(sanitizedEntry)
        }
    }

    /// Force flush all pending logs
    public func flush() {
        logBatcher?.flush()
    }

    // MARK: - Private Methods

    private func setupBatcher() {
        guard configuration.enableRemoteLogging else { return }

        logBatcher = LogBatcher(configuration: configuration) { [weak self] logs in
            guard let self = self,
                  let endpoint = self.configuration.remoteEndpoint else { return }

            Task {
                await self.remoteLogger.submitLogs(logs, endpoint: endpoint)
            }
        }
    }

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

        // Set minimum log level from environment
        config.minLogLevel = envConfig.logging.minimumLogLevel

        // Enable/disable remote logging based on environment
        config.enableRemoteLogging = envConfig.logging.enableRemoteLogging

        // Enable local logging based on environment console logging
        config.enableLocalLogging = envConfig.logging.enableConsoleLogging || envConfig.logging.enableFileLogging

        // Update configuration
        self.configuration = config

        // Configure Pulse
        configurePulse()

        // Log current environment for debugging
        if envConfig.environment.isDebug {
            let entry = LogEntry(
                timestamp: Date(),
                level: .info,
                category: "LoggingManager",
                message: "🚀 Running in \(envConfig.environment.rawValue) environment - Remote: \(envConfig.logging.enableRemoteLogging), MinLevel: \(envConfig.logging.minimumLogLevel)",
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
