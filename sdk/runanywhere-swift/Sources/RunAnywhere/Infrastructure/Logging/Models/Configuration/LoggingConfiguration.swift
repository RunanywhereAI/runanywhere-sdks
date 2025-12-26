//
//  LoggingConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration settings for the logging system
//

import Foundation

/// Logging configuration for the SDK
public struct LoggingConfiguration: Sendable {

    // MARK: - Properties

    /// Enable local logging (console/Pulse)
    public var enableLocalLogging: Bool

    /// Minimum log level filter
    public var minLogLevel: LogLevel

    /// Include device metadata in logs
    public var includeDeviceMetadata: Bool

    /// Enable Sentry logging for crash reporting and error tracking
    public var enableSentryLogging: Bool

    // MARK: - Initialization

    /// Initialize with default values
    public init(
        enableLocalLogging: Bool = true,
        minLogLevel: LogLevel = .info,
        includeDeviceMetadata: Bool = true,
        enableSentryLogging: Bool = false
    ) {
        self.enableLocalLogging = enableLocalLogging
        self.minLogLevel = minLogLevel
        self.includeDeviceMetadata = includeDeviceMetadata
        self.enableSentryLogging = enableSentryLogging
    }
}

// MARK: - Environment Presets

extension LoggingConfiguration {

    /// Configuration preset for development environment
    /// Sentry logging is enabled by default for development
    public static var development: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .debug,
            includeDeviceMetadata: false,
            enableSentryLogging: true
        )
    }

    /// Configuration preset for staging environment
    public static var staging: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .info,
            includeDeviceMetadata: true,
            enableSentryLogging: false
        )
    }

    /// Configuration preset for production environment
    public static var production: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: false,
            minLogLevel: .warning,
            includeDeviceMetadata: true,
            enableSentryLogging: false
        )
    }
}
