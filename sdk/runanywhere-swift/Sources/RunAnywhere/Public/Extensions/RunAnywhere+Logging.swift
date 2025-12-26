//
//  RunAnywhere+Logging.swift
//  RunAnywhere SDK
//
//  Extension for configuring logging
//

import Foundation

extension RunAnywhere {

    // MARK: - Logging Configuration

    /// Configure logging with a predefined configuration
    /// - Parameter config: The logging configuration to apply
    public static func configureLogging(_ config: LoggingConfiguration) {
        Logging.shared.configure(config)
    }

    /// Enable or disable local console logging
    /// - Parameter enabled: Whether to enable local logging
    public static func setLocalLoggingEnabled(_ enabled: Bool) {
        Logging.shared.setLocalLoggingEnabled(enabled)
    }

    /// Set minimum log level for SDK logging
    /// - Parameter level: Minimum log level to capture
    public static func setLogLevel(_ level: LogLevel) {
        Logging.shared.setMinLogLevel(level)
    }

    /// Enable or disable Sentry error tracking
    /// - Parameter enabled: Whether to enable Sentry logging
    public static func setSentryLoggingEnabled(_ enabled: Bool) {
        Logging.shared.setSentryLoggingEnabled(enabled)
    }

    /// Add a custom log destination
    /// - Parameter destination: The destination to add
    public static func addLogDestination(_ destination: LogDestination) {
        Logging.shared.addDestination(destination)
    }

    // MARK: - Debugging Helpers

    /// Enable verbose debugging mode
    /// - Parameter enabled: Whether to enable verbose mode
    public static func setDebugMode(_ enabled: Bool) {
        setLogLevel(enabled ? .debug : .info)
        setLocalLoggingEnabled(enabled)
    }

    /// Force flush all pending logs to destinations
    public static func flushLogs() {
        Logging.shared.flush()
    }
}
