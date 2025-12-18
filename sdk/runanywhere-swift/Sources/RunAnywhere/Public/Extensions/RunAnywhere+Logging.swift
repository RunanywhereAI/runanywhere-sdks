//
//  RunAnywhere+Logging.swift
//  RunAnywhere SDK
//
//  Extension for configuring logging
//

import Foundation

extension RunAnywhere {

    // MARK: - Logging Configuration

    /// Enable or disable local logging via Pulse
    /// - Parameter enabled: Whether to enable local Pulse logging
    public static func configureLocalLogging(enabled: Bool) {
        Logging.shared.setLocalLoggingEnabled(enabled)
    }

    /// Set minimum log level for SDK logging
    /// - Parameter level: Minimum log level to capture
    public static func setLogLevel(_ level: LogLevel) {
        Logging.shared.setMinLogLevel(level)
    }

    // MARK: - Debugging Helpers

    /// Enable verbose debugging mode
    /// - Parameter enabled: Whether to enable verbose mode
    public static func setDebugMode(_ enabled: Bool) {
        // Update log level based on debug mode
        setLogLevel(enabled ? .debug : .info)

        // Update local logging
        configureLocalLogging(enabled: enabled)
    }

    /// Force flush all pending logs and analytics
    public static func flushAll() async {
        // Flush SDK logs
        Logging.shared.flush()

        // Flush analytics events
        await AnalyticsQueueManager.shared.flush()
    }
}
