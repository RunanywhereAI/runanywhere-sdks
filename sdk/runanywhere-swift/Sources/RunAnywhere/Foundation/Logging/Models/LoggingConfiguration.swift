//
//  LoggingConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration settings for the logging system
//

import Foundation

/// Logging configuration for local debugging
public struct LoggingConfiguration {
    /// Enable local logging (console/Pulse)
    public var enableLocalLogging: Bool = true

    /// Minimum log level filter
    public var minLogLevel: LogLevel = .info

    /// Include device metadata in logs
    public var includeDeviceMetadata: Bool = true

    public init() {}
}
