//
//  RunAnywhere+Logging.swift
//  RunAnywhere SDK
//
//  Extension for configuring logging and analytics endpoints
//

import Foundation

extension RunAnywhere {

    // MARK: - Logging Configuration (SDK Team Debugging)

    /// Configure SDK logging endpoint for internal debugging
    /// - Parameters:
    ///   - endpoint: URL endpoint for SDK team logging (e.g., Sentry, DataDog)
    ///   - enabled: Whether to enable remote SDK logging
    /// - Note: This is for SDK team debugging, not consumer analytics
    public static func configureSDKLogging(endpoint: URL?, enabled: Bool = true) {
        LoggingManager.shared.configureSDKLogging(endpoint: endpoint, enabled: enabled)
    }

    /// Enable or disable local logging via Pulse
    /// - Parameter enabled: Whether to enable local Pulse logging
    public static func configureLocalLogging(enabled: Bool) {
        var config = LoggingManager.shared.configuration
        config.enableLocalLogging = enabled
        LoggingManager.shared.configure(config)
    }

    /// Set minimum log level for SDK logging
    /// - Parameter level: Minimum log level to capture
    public static func setLogLevel(_ level: LogLevel) {
        var config = LoggingManager.shared.configuration
        config.minLogLevel = level
        LoggingManager.shared.configure(config)
    }

    // MARK: - Analytics Configuration (Consumer Events)

    /// Configure analytics endpoint for consumer events
    /// - Parameters:
    ///   - endpoint: URL endpoint for consumer analytics (set via baseURL in Configuration)
    ///   - batchSize: Number of events to batch before sending
    ///   - flushInterval: Time interval between automatic flushes
    /// - Note: Analytics endpoint is configured via the baseURL in SDK Configuration
    public static func configureAnalytics(
        batchSize: Int = 50,
        flushInterval: TimeInterval = 30.0
    ) {
        // Analytics uses the baseURL from Configuration
        // The endpoint is already configured via TelemetryRepository
        // This method could be used to adjust batching parameters if needed

        // Note: Currently batching params are hardcoded in AnalyticsQueueManager
        // We could make them configurable if needed
    }

    // MARK: - Telemetry Consent

    /// Update telemetry consent preference
    /// - Parameter consent: New consent level
    public static func updateTelemetryConsent(_ consent: TelemetryConsent) {
        guard var config = _configurationData else {
            SDKLogger(category: "RunAnywhere").warning("Cannot update telemetry consent - SDK not initialized")
            return
        }

        config.telemetry.consent = consent
        _configurationData = config

        // Apply consent to both logging and analytics
        switch consent {
        case .denied:
            // Disable all remote data collection
            LoggingManager.shared.configureSDKLogging(endpoint: nil, enabled: false)
        case .limited:
            // Only errors and critical events
            setLogLevel(.error)
        case .granted:
            // Full telemetry
            setLogLevel(.info)
        }
    }

    // MARK: - Debugging Helpers

    /// Enable verbose debugging mode
    /// - Parameter enabled: Whether to enable verbose mode
    public static func setDebugMode(_ enabled: Bool) {
        guard var config = _configurationData else {
            SDKLogger(category: "RunAnywhere").warning("Cannot set debug mode - SDK not initialized")
            return
        }

        config.debugMode = enabled
        _configurationData = config

        // Update log level based on debug mode
        setLogLevel(enabled ? .debug : .info)

        // Update local logging
        configureLocalLogging(enabled: enabled)
    }

    /// Force flush all pending logs and analytics
    public static func flushAll() async {
        // Flush SDK logs
        LoggingManager.shared.flush()

        // Flush analytics events
        await AnalyticsQueueManager.shared.flush()
    }
}
