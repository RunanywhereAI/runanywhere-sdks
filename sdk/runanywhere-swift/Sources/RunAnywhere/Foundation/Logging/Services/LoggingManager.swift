//
//  LoggingManager.swift
//  RunAnywhere SDK
//
//  Central logging coordination service using Pulse for local debugging
//

import Foundation
import Pulse

/// Centralized logging manager for the SDK
/// Uses Pulse for local logging and debugging
public class LoggingManager {

    // MARK: - Singleton

    public static let shared = LoggingManager()

    // MARK: - Properties

    /// Current logging configuration (protected by lock)
    private let _configuration = UnfairLockWithState(initialState: LoggingConfiguration())

    public var configuration: LoggingConfiguration {
        get {
            _configuration.withLock { (state: LoggingConfiguration) -> LoggingConfiguration in
                return state
            }
        }
        set {
            _configuration.withLock { (state: inout LoggingConfiguration) in
                state = newValue
            }
        }
    }

    /// SDK Environment
    private let environment: SDKEnvironment

    /// Pulse logger for local debugging and development
    private let pulseLogger = LoggerStore.shared

    // MARK: - Initialization

    private init() {
        // Get environment from RunAnywhere initialization
        self.environment = RunAnywhere.currentEnvironment ?? .production

        // Apply environment-based configuration
        applyEnvironmentConfiguration()
    }

    // MARK: - Public Methods

    /// Update logging configuration
    public func configure(_ config: LoggingConfiguration) {
        _configuration.withLock { $0 = config }
    }

    /// Log a message with the specified level and metadata
    internal func log(level: LogLevel, category: String, message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        // Check against SDK configuration minimum log level
        guard level >= configuration.minLogLevel else { return }

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
            logToPulse(entry)
        }
    }

    /// Force flush all pending logs
    public func flush() {
        // Pulse handles its own flushing
    }

    // MARK: - Private Methods

    private func logToPulse(_ entry: LogEntry) {
        var pulseMetadata: [String: LoggerStore.MetadataValue] = [:]

        // Add category
        pulseMetadata["category"] = .string(entry.category)

        // Convert metadata to Pulse format
        if let metadata = entry.metadata {
            for (key, value) in metadata {
                // Skip internal markers
                if key.hasPrefix("__") { continue }

                pulseMetadata[key] = convertToMetadataValue(value)
            }
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

    // swiftlint:disable:next avoid_any_type
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

    private func applyEnvironmentConfiguration() {
        // Update SDK configuration based on environment
        var config = configuration

        // Set defaults based on environment
        switch environment {
        case .development:
            config.enableLocalLogging = true
            config.minLogLevel = .debug
            config.includeDeviceMetadata = false
        case .staging:
            config.enableLocalLogging = true
            config.minLogLevel = .info
            config.includeDeviceMetadata = true
        case .production:
            config.enableLocalLogging = false
            config.minLogLevel = .warning
            config.includeDeviceMetadata = true
        }

        // Update configuration
        self.configuration = config

        // Configure Pulse
        configurePulse()
    }

    private func configurePulse() {
        // Enable automatic network logging
        URLSessionProxyDelegate.enableAutomaticRegistration()
    }
}
