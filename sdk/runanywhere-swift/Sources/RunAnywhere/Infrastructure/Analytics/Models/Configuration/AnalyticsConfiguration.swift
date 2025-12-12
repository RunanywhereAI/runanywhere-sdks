//
//  AnalyticsConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for analytics capability
//

import Foundation

/// Configuration for the Analytics capability
public struct AnalyticsConfiguration: Sendable {

    // MARK: - Queue Settings

    /// Maximum number of events to batch before flushing
    public var batchSize: Int

    /// Interval in seconds between automatic flushes
    public var flushInterval: TimeInterval

    /// Maximum number of retry attempts for failed operations
    public var maxRetries: Int

    // MARK: - Storage Settings

    /// Whether to persist events locally before syncing
    public var enableLocalPersistence: Bool

    /// Maximum age of events to keep locally (in days)
    public var retentionDays: Int

    /// Maximum number of events to store locally
    public var maxLocalEvents: Int

    // MARK: - Sync Settings

    /// Whether to sync events to remote server
    public var enableRemoteSync: Bool

    /// Whether to sync only on WiFi
    public var syncOnlyOnWiFi: Bool

    // MARK: - Privacy Settings

    /// Whether to include device information in events
    public var includeDeviceInfo: Bool

    /// Whether to anonymize user data
    public var anonymizeData: Bool

    // MARK: - Debug Settings

    /// Whether to enable verbose logging
    public var debugLogging: Bool

    // MARK: - Initialization

    public init(
        batchSize: Int = 50,
        flushInterval: TimeInterval = 30.0,
        maxRetries: Int = 3,
        enableLocalPersistence: Bool = true,
        retentionDays: Int = 30,
        maxLocalEvents: Int = 10000,
        enableRemoteSync: Bool = true,
        syncOnlyOnWiFi: Bool = false,
        includeDeviceInfo: Bool = true,
        anonymizeData: Bool = false,
        debugLogging: Bool = false
    ) {
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.maxRetries = maxRetries
        self.enableLocalPersistence = enableLocalPersistence
        self.retentionDays = retentionDays
        self.maxLocalEvents = maxLocalEvents
        self.enableRemoteSync = enableRemoteSync
        self.syncOnlyOnWiFi = syncOnlyOnWiFi
        self.includeDeviceInfo = includeDeviceInfo
        self.anonymizeData = anonymizeData
        self.debugLogging = debugLogging
    }

    // MARK: - Presets

    /// Default configuration for production use
    public static let `default` = AnalyticsConfiguration()

    /// Configuration optimized for development
    public static let development = AnalyticsConfiguration(
        batchSize: 10,
        flushInterval: 5.0,
        enableRemoteSync: false,
        debugLogging: true
    )

    /// Configuration with minimal data collection
    public static let minimal = AnalyticsConfiguration(
        enableLocalPersistence: false,
        enableRemoteSync: false,
        includeDeviceInfo: false,
        anonymizeData: true
    )
}

// MARK: - Validation

extension AnalyticsConfiguration {
    /// Validate the configuration
    public func validate() throws {
        guard batchSize > 0 else {
            throw AnalyticsError.invalidConfiguration(reason: "Batch size must be greater than 0")
        }
        guard flushInterval > 0 else {
            throw AnalyticsError.invalidConfiguration(reason: "Flush interval must be greater than 0")
        }
        guard maxRetries >= 0 else {
            throw AnalyticsError.invalidConfiguration(reason: "Max retries cannot be negative")
        }
        guard retentionDays > 0 else {
            throw AnalyticsError.invalidConfiguration(reason: "Retention days must be greater than 0")
        }
        guard maxLocalEvents > 0 else {
            throw AnalyticsError.invalidConfiguration(reason: "Max local events must be greater than 0")
        }
    }
}
