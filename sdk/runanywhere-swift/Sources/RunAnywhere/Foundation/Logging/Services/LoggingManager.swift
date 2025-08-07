//
//  LoggingManager.swift
//  RunAnywhere SDK
//
//  Central logging coordination service
//

import Foundation
import os.log

/// Centralized logging manager for the SDK
public class LoggingManager {

    // MARK: - Singleton

    public static let shared = LoggingManager()

    // MARK: - Properties

    /// Current logging configuration
    public private(set) var configuration = LoggingConfiguration()

    /// Environment configuration
    private let envConfig = EnvironmentConfiguration.current

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

    /// Log a message with the specified level and metadata
    internal func log(level: LogLevel, category: String, message: String, metadata: [String: Any]? = nil) {
        // Check against environment minimum log level first
        guard level >= envConfig.logging.minimumLogLevel else { return }

        // Then check against SDK configuration
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

        // Local logging - respect environment configuration
        if configuration.enableLocalLogging && envConfig.logging.enableConsoleLogging {
            logLocally(entry)
        }

        // File logging - if enabled in environment
        if envConfig.logging.enableFileLogging {
            // TODO: Implement file logging
        }

        // Remote logging - respect both SDK and environment configuration
        if configuration.enableRemoteLogging && envConfig.logging.enableRemoteLogging {
            logBatcher?.add(entry)
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

    private func logLocally(_ entry: LogEntry) {
        let formattedMessage = LogFormatter.formatForOSLog(entry)

        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            let logger = os.Logger(subsystem: "com.runanywhere.sdk", category: entry.category)

            switch entry.level {
            case .debug:
                logger.debug("\(formattedMessage)")
            case .info:
                logger.info("\(formattedMessage)")
            case .warning:
                logger.warning("\(formattedMessage)")
            case .error:
                logger.error("\(formattedMessage)")
            case .fault:
                logger.fault("\(formattedMessage)")
            }
        } else {
            // Fallback for older OS versions
            let consoleMessage = LogFormatter.formatForConsole(entry)
            // Only print to console if environment allows it
            if envConfig.logging.enableConsoleLogging {
                print(consoleMessage)
            }
        }
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

        // Log current environment for debugging
        if envConfig.environment.isDebug {
            let entry = LogEntry(
                timestamp: Date(),
                level: .info,
                category: "LoggingManager",
                message: "🚀 Running in \(envConfig.environment.rawValue) environment - Console: \(envConfig.logging.enableConsoleLogging), Remote: \(envConfig.logging.enableRemoteLogging), MinLevel: \(envConfig.logging.minimumLogLevel)",
                metadata: nil,
                deviceInfo: nil
            )
            logLocally(entry)
        }
    }
}
