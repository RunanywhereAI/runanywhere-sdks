//
//  LoggingService.swift
//  RunAnywhere SDK
//
//  Core service protocol for logging operations
//  Defines the interface for logging, configuration, and destination management
//

import Foundation

/// Protocol defining logging service capabilities
/// Implementations provide log routing, filtering, and destination management
public protocol LoggingService: AnyObject { // swiftlint:disable:this avoid_any_object

    // MARK: - Configuration

    /// Current logging configuration
    var configuration: LoggingConfiguration { get set }

    /// Update logging configuration
    /// - Parameter config: The new configuration to apply
    func configure(_ config: LoggingConfiguration)

    // MARK: - Core Logging Operations

    /// Log a message with the specified level and metadata
    /// - Parameters:
    ///   - level: The severity level of the log
    ///   - category: The category/subsystem for the log
    ///   - message: The log message
    ///   - metadata: Optional additional context
    func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? // swiftlint:disable:this prefer_concrete_types avoid_any_type
    )

    // MARK: - Destination Management

    /// Register a log destination
    /// - Parameter destination: The destination to add
    func addDestination(_ destination: LogDestination)

    /// Remove a log destination
    /// - Parameter destination: The destination to remove
    func removeDestination(_ destination: LogDestination)

    /// Get all registered destinations
    var destinations: [LogDestination] { get }

    // MARK: - Lifecycle

    /// Force flush all pending logs to all destinations
    func flush()
}

// MARK: - Default Implementations

extension LoggingService {
    /// Convenience method to log without metadata
    public func log(level: LogLevel, category: String, message: String) {
        log(level: level, category: category, message: message, metadata: nil)
    }
}
