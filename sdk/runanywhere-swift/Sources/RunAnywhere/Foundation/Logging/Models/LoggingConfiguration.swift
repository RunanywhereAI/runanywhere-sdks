//
//  LoggingConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration settings for the logging system
//

import Foundation

/// Logging configuration
public struct LoggingConfiguration {
    /// Enable local logging (console/os_log)
    public var enableLocalLogging: Bool = true

    /// Enable remote logging (telemetry)
    public var enableRemoteLogging: Bool = false

    /// Enable analytics event logging
    public var enableAnalyticsLogging: Bool = false

    /// Enable verbose/debug logging
    public var enableVerboseLogging: Bool = false

    /// Remote logging endpoint
    public var remoteEndpoint: URL?

    /// Log level filter
    public var minLogLevel: LogLevel = .info

    /// Include device metadata in remote logs
    public var includeDeviceMetadata: Bool = true

    /// Maximum log entries to batch before sending
    public var batchSize: Int = 100

    /// Maximum time to wait before sending logs (seconds)
    public var batchInterval: TimeInterval = 60

    public init() {}
}
