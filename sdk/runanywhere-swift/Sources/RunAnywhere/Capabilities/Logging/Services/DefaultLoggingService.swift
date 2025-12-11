//
//  DefaultLoggingService.swift
//  RunAnywhere SDK
//
//  Default implementation of the LoggingService protocol
//  Manages log routing to registered destinations with filtering
//

import Foundation
import os

/// Default implementation of the LoggingService
/// Manages log destinations and handles log filtering based on configuration
public final class DefaultLoggingService: LoggingService {

    // MARK: - Properties

    /// Current logging configuration (protected by OSAllocatedUnfairLock - Swift 6 pattern)
    private let _configuration: OSAllocatedUnfairLock<LoggingConfiguration>

    public var configuration: LoggingConfiguration {
        get {
            _configuration.withLock { $0 }
        }
        set {
            _configuration.withLock { $0 = newValue }
        }
    }

    /// Registered log destinations (protected by OSAllocatedUnfairLock)
    private let _destinations: OSAllocatedUnfairLock<[LogDestination]>

    public var destinations: [LogDestination] {
        _destinations.withLock { $0 }
    }

    // MARK: - Initialization

    /// Initialize with default configuration
    public init() {
        self._configuration = OSAllocatedUnfairLock(initialState: LoggingConfiguration())
        self._destinations = OSAllocatedUnfairLock(initialState: [])

        // Add default Pulse destination
        addDestination(PulseDestination())
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The logging configuration to use
    public init(configuration: LoggingConfiguration) {
        self._configuration = OSAllocatedUnfairLock(initialState: configuration)
        self._destinations = OSAllocatedUnfairLock(initialState: [])

        // Add default Pulse destination if local logging is enabled
        if configuration.enableLocalLogging {
            addDestination(PulseDestination())
        }
    }

    // MARK: - LoggingService

    public func configure(_ config: LoggingConfiguration) {
        _configuration.withLock { $0 = config }
    }

    public func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? // swiftlint:disable:this prefer_concrete_types avoid_any_type
    ) {
        // Check against minimum log level
        let currentConfig = configuration
        guard level >= currentConfig.minLogLevel else { return }

        // Check if local logging is enabled
        guard currentConfig.enableLocalLogging else { return }

        // Create log entry
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            deviceInfo: currentConfig.includeDeviceMetadata ? DeviceInfo.current : nil
        )

        // Write to all available destinations
        let currentDestinations = destinations
        for destination in currentDestinations where destination.isAvailable {
            destination.write(entry)
        }
    }

    public func addDestination(_ destination: LogDestination) {
        _destinations.withLock { destinations in
            // Avoid duplicates
            if !destinations.contains(where: { $0.identifier == destination.identifier }) {
                destinations.append(destination)
            }
        }
    }

    public func removeDestination(_ destination: LogDestination) {
        _destinations.withLock { destinations in
            destinations.removeAll { $0.identifier == destination.identifier }
        }
    }

    public func flush() {
        let currentDestinations = destinations
        for destination in currentDestinations {
            destination.flush()
        }
    }
}

// MARK: - Environment Configuration

extension DefaultLoggingService {

    /// Apply configuration based on SDK environment
    /// - Parameter environment: The SDK environment
    public func applyEnvironmentConfiguration(_ environment: SDKEnvironment) {
        let config: LoggingConfiguration
        switch environment {
        case .development:
            config = .development
        case .staging:
            config = .staging
        case .production:
            config = .production
        }
        configure(config)
    }
}
