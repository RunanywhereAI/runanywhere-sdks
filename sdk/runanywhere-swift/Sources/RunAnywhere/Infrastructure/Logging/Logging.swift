//
//  Logging.swift
//  RunAnywhere SDK
//
//  Public entry point for the Logging capability
//  Provides access to logging operations and configuration
//

import Foundation

/// Public entry point for the Logging capability
/// Provides simplified access to logging operations and configuration management
public final class Logging {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Logging()

    // MARK: - Properties

    private let loggingService: LoggingService

    // MARK: - Initialization

    /// Initialize with default logging service
    public convenience init() {
        let environment = RunAnywhere.currentEnvironment ?? .production
        let configuration = Self.configurationForEnvironment(environment)
        let service = DefaultLoggingService(configuration: configuration)
        self.init(loggingService: service)
    }

    /// Initialize with custom logging service (for testing or customization)
    /// - Parameter loggingService: The logging service to use
    internal init(loggingService: LoggingService) {
        self.loggingService = loggingService
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The logging configuration to use
    public convenience init(configuration: LoggingConfiguration) {
        let service = DefaultLoggingService(configuration: configuration)
        self.init(loggingService: service)
    }

    // MARK: - Public API

    /// Access the underlying logging service
    /// Provides low-level logging operations if needed
    public var service: LoggingService {
        return loggingService
    }

    /// Current logging configuration
    public var configuration: LoggingConfiguration {
        get { loggingService.configuration }
        set { loggingService.configuration = newValue }
    }

    // MARK: - Convenience Methods

    /// Update logging configuration
    /// - Parameter config: The new configuration to apply
    public func configure(_ config: LoggingConfiguration) {
        loggingService.configure(config)
    }

    /// Log a message with the specified level
    /// - Parameters:
    ///   - level: The severity level
    ///   - category: The category/subsystem
    ///   - message: The log message
    ///   - metadata: Optional additional context
    public func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? = nil // swiftlint:disable:this prefer_concrete_types avoid_any_type
    ) {
        loggingService.log(level: level, category: category, message: message, metadata: metadata)
    }

    /// Force flush all pending logs
    public func flush() {
        loggingService.flush()
    }

    // MARK: - Configuration Helpers

    /// Enable or disable local logging
    /// - Parameter enabled: Whether to enable local logging
    public func setLocalLoggingEnabled(_ enabled: Bool) {
        var config = configuration
        config.enableLocalLogging = enabled
        configure(config)
    }

    /// Set the minimum log level
    /// - Parameter level: The minimum log level to capture
    public func setMinLogLevel(_ level: LogLevel) {
        var config = configuration
        config.minLogLevel = level
        configure(config)
    }

    /// Set whether to include device metadata in logs
    /// - Parameter include: Whether to include device metadata
    public func setIncludeDeviceMetadata(_ include: Bool) {
        var config = configuration
        config.includeDeviceMetadata = include
        configure(config)
    }

    // MARK: - Destination Management

    /// Add a custom log destination
    /// - Parameter destination: The destination to add
    public func addDestination(_ destination: LogDestination) {
        loggingService.addDestination(destination)
    }

    /// Remove a log destination
    /// - Parameter destination: The destination to remove
    public func removeDestination(_ destination: LogDestination) {
        loggingService.removeDestination(destination)
    }

    /// Get all registered destinations
    public var destinations: [LogDestination] {
        loggingService.destinations
    }

    // MARK: - Private Helpers

    private static func configurationForEnvironment(_ environment: SDKEnvironment) -> LoggingConfiguration {
        switch environment {
        case .development:
            return .development
        case .staging:
            return .staging
        case .production:
            return .production
        }
    }
}
