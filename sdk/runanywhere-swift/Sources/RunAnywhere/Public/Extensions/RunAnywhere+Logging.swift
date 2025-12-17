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

    // MARK: - Analytics Configuration (Consumer Events)

    /// Configure analytics endpoint for consumer events
    /// - Parameters:
    ///   - batchSize: Number of events to batch before sending
    ///   - flushInterval: Time interval between automatic flushes
    /// - Note: Analytics endpoint is configured via the baseURL in SDK Configuration
    public static func configureAnalytics(
        batchSize _: Int = 50,
        flushInterval _: TimeInterval = 30.0
    ) {
        // Analytics uses the baseURL from Configuration
        // The endpoint is already configured via TelemetryRepository
        // This method could be used to adjust batching parameters if needed
    }

    // MARK: - Debugging Helpers

    /// Enable verbose debugging mode
    /// - Parameter enabled: Whether to enable verbose mode
    public static func setDebugMode(_ enabled: Bool) {
        guard var config = configurationData else {
            SDKLogger(category: "RunAnywhere").warning("Cannot set debug mode - SDK not initialized")
            return
        }

        config.debugMode = enabled
        configurationData = config

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
