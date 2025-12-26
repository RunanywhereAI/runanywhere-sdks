//
//  LoggingService.swift
//  RunAnywhere SDK
//
//  Production-ready logging service with destination routing.
//  Thread-safe, supports multiple destinations (Pulse, Sentry).
//

import Foundation
import os

// MARK: - Logging

/// Central logging service for the RunAnywhere SDK.
/// Provides thread-safe logging with configurable destinations and filtering.
///
/// ## Usage
/// ```swift
/// // Log via SDKLogger (recommended)
/// let logger = SDKLogger(category: "MyFeature")
/// logger.info("Operation completed")
///
/// // Or directly via Logging
/// Logging.shared.log(level: .info, category: "App", message: "Hello")
/// ```
public final class Logging: @unchecked Sendable {

    // MARK: - Shared Instance

    /// Shared singleton instance
    public static let shared = Logging()

    // MARK: - Properties

    /// Current logging configuration (thread-safe via OSAllocatedUnfairLock)
    private let _configuration: OSAllocatedUnfairLock<LoggingConfiguration>

    public var configuration: LoggingConfiguration {
        get { _configuration.withLock { $0 } }
        set { _configuration.withLock { $0 = newValue } }
    }

    /// Registered log destinations (thread-safe via OSAllocatedUnfairLock)
    private let _destinations: OSAllocatedUnfairLock<[LogDestination]>

    public var destinations: [LogDestination] {
        _destinations.withLock { $0 }
    }

    // MARK: - Initialization

    private init() {
        let environment = RunAnywhere.currentEnvironment ?? .production
        let config = Self.configurationForEnvironment(environment)

        self._configuration = OSAllocatedUnfairLock(initialState: config)
        self._destinations = OSAllocatedUnfairLock(initialState: [])

        // Add default Pulse destination if local logging is enabled
        if config.enableLocalLogging {
            addDestination(PulseDestination())
        }

        // Add Sentry destination if Sentry logging is enabled
        if config.enableSentryLogging {
            setupSentryLogging()
        }
    }

    // MARK: - Configuration

    /// Update logging configuration
    public func configure(_ config: LoggingConfiguration) {
        _configuration.withLock { $0 = config }
    }

    /// Enable or disable local logging
    public func setLocalLoggingEnabled(_ enabled: Bool) {
        var config = configuration
        config.enableLocalLogging = enabled
        configure(config)
    }

    /// Set the minimum log level
    public func setMinLogLevel(_ level: LogLevel) {
        var config = configuration
        config.minLogLevel = level
        configure(config)
    }

    /// Set whether to include device metadata in logs
    public func setIncludeDeviceMetadata(_ include: Bool) {
        var config = configuration
        config.includeDeviceMetadata = include
        configure(config)
    }

    /// Enable or disable Sentry logging for crash reporting
    public func setSentryLoggingEnabled(_ enabled: Bool) {
        var config = configuration
        config.enableSentryLogging = enabled
        configure(config)

        if enabled {
            let environment = RunAnywhere.currentEnvironment ?? .development
            SentryManager.shared.initialize(environment: environment)
            addDestination(SentryDestination())
        } else {
            if let sentryDest = destinations.first(where: { $0.identifier == "com.runanywhere.logging.sentry" }) {
                removeDestination(sentryDest)
            }
        }
    }

    // MARK: - Core Logging

    /// Log a message with the specified level and metadata
    public func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? = nil // swiftlint:disable:this prefer_concrete_types avoid_any_type
    ) {
        let currentConfig = configuration

        // Check against minimum log level
        guard level >= currentConfig.minLogLevel else { return }

        // Check if any logging is enabled
        guard currentConfig.enableLocalLogging || currentConfig.enableSentryLogging else { return }

        // Sanitize metadata to prevent logging sensitive information
        let sanitizedMetadata = sanitizeMetadata(metadata)

        // Create log entry
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: sanitizedMetadata,
            deviceInfo: currentConfig.includeDeviceMetadata ? DeviceInfo.current : nil
        )

        // Write to all available destinations
        let currentDestinations = destinations
        for destination in currentDestinations where destination.isAvailable {
            destination.write(entry)
        }
    }

    // MARK: - Destination Management

    /// Add a log destination
    public func addDestination(_ destination: LogDestination) {
        _destinations.withLock { destinations in
            // Avoid duplicates
            if !destinations.contains(where: { $0.identifier == destination.identifier }) {
                destinations.append(destination)
            }
        }
    }

    /// Remove a log destination
    public func removeDestination(_ destination: LogDestination) {
        _destinations.withLock { destinations in
            destinations.removeAll { $0.identifier == destination.identifier }
        }
    }

    /// Force flush all pending logs to all destinations
    public func flush() {
        let currentDestinations = destinations
        for destination in currentDestinations {
            destination.flush()
        }
    }

    // MARK: - Private Helpers

    private func setupSentryLogging() {
        let environment = RunAnywhere.currentEnvironment ?? .development
        SentryManager.shared.initialize(environment: environment)
        addDestination(SentryDestination())
    }

    private static func configurationForEnvironment(_ environment: SDKEnvironment) -> LoggingConfiguration {
        switch environment {
        case .development: return .development
        case .staging: return .staging
        case .production: return .production
        }
    }

    /// Keys that contain sensitive information and should be redacted
    private static let sensitiveKeys: Set<String> = [
        "apikey", "api_key", "apiKey",
        "password", "passwd", "pwd",
        "secret", "secretkey", "secret_key", "secretKey",
        "token", "accesstoken", "access_token", "accessToken",
        "refreshtoken", "refresh_token", "refreshToken",
        "authorization", "auth",
        "bearer", "credential", "credentials",
        "privatekey", "private_key", "privateKey"
    ]

    /// Sanitize metadata dictionary to redact sensitive values
    private func sanitizeMetadata(_ metadata: [String: Any]?) -> [String: Any]? { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        guard let metadata = metadata else { return nil }

        var sanitized: [String: Any] = [:] // swiftlint:disable:this prefer_concrete_types avoid_any_type
        for (key, value) in metadata {
            let lowercasedKey = key.lowercased()
            if Self.sensitiveKeys.contains(lowercasedKey) ||
               lowercasedKey.contains("key") ||
               lowercasedKey.contains("secret") ||
               lowercasedKey.contains("password") ||
               lowercasedKey.contains("token") ||
               lowercasedKey.contains("auth") {
                sanitized[key] = "[REDACTED]"
            } else if let nestedDict = value as? [String: Any] { // swiftlint:disable:this avoid_any_type
                sanitized[key] = sanitizeMetadata(nestedDict) ?? [:]
            } else {
                sanitized[key] = value
            }
        }
        return sanitized
    }
}

// MARK: - Environment Configuration Extension

extension Logging {

    /// Apply configuration based on SDK environment
    public func applyEnvironmentConfiguration(_ environment: SDKEnvironment) {
        let config = Self.configurationForEnvironment(environment)
        configure(config)

        // Setup Sentry if enabled in the new configuration
        if config.enableSentryLogging {
            setupSentryLogging()
        }
    }
}
