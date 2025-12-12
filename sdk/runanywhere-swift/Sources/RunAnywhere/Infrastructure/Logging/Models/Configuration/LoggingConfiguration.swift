//
//  LoggingConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration settings for the logging system
//

import Foundation

/// Logging configuration for local debugging
public struct LoggingConfiguration: Sendable {

    // MARK: - Properties

    /// Enable local logging (console/Pulse)
    public var enableLocalLogging: Bool

    /// Minimum log level filter
    public var minLogLevel: LogLevel

    /// Include device metadata in logs
    public var includeDeviceMetadata: Bool

    // MARK: - Initialization

    /// Initialize with default values
    public init() {
        self.enableLocalLogging = true
        self.minLogLevel = .info
        self.includeDeviceMetadata = true
    }

    /// Initialize with custom values
    /// - Parameters:
    ///   - enableLocalLogging: Whether to enable local logging
    ///   - minLogLevel: Minimum log level to capture
    ///   - includeDeviceMetadata: Whether to include device metadata
    public init(
        enableLocalLogging: Bool = true,
        minLogLevel: LogLevel = .info,
        includeDeviceMetadata: Bool = true
    ) {
        self.enableLocalLogging = enableLocalLogging
        self.minLogLevel = minLogLevel
        self.includeDeviceMetadata = includeDeviceMetadata
    }

    // MARK: - Validation

    /// Validate the configuration
    /// - Throws: LoggingError if configuration is invalid
    public func validate() throws {
        // Currently all configurations are valid
        // Add validation rules here if needed in the future
    }
}

// MARK: - Builder Pattern

extension LoggingConfiguration {

    /// Create configuration with builder pattern
    /// - Returns: A new Builder instance
    public static func builder() -> Builder {
        Builder()
    }

    /// Builder for LoggingConfiguration
    public class Builder {
        private var config = LoggingConfiguration()

        /// Set whether local logging is enabled
        public func enableLocalLogging(_ enabled: Bool) -> Builder {
            config.enableLocalLogging = enabled
            return self
        }

        /// Set the minimum log level
        public func minLogLevel(_ level: LogLevel) -> Builder {
            config.minLogLevel = level
            return self
        }

        /// Set whether to include device metadata
        public func includeDeviceMetadata(_ include: Bool) -> Builder {
            config.includeDeviceMetadata = include
            return self
        }

        /// Build the configuration
        public func build() -> LoggingConfiguration {
            config
        }
    }
}

// MARK: - Environment Presets

extension LoggingConfiguration {

    /// Configuration preset for development environment
    public static var development: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .debug,
            includeDeviceMetadata: false
        )
    }

    /// Configuration preset for staging environment
    public static var staging: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .info,
            includeDeviceMetadata: true
        )
    }

    /// Configuration preset for production environment
    public static var production: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: false,
            minLogLevel: .warning,
            includeDeviceMetadata: true
        )
    }
}
