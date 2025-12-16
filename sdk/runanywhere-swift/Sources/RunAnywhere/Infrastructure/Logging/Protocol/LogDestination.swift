//
//  LogDestination.swift
//  RunAnywhere SDK
//
//  Protocol for log destinations (Pulse, Console, File, etc.)
//

import Foundation

/// Protocol for log output destinations
/// Implementations handle writing logs to specific backends (Pulse, Console, File, etc.)
public protocol LogDestination: AnyObject { // swiftlint:disable:this avoid_any_object

    // MARK: - Identification

    /// Unique identifier for this destination
    var identifier: String { get }

    /// Human-readable name for this destination
    var name: String { get }

    // MARK: - State

    /// Whether this destination is currently available for writing
    var isAvailable: Bool { get }

    // MARK: - Operations

    /// Write a log entry to this destination
    /// - Parameter entry: The log entry to write
    func write(_ entry: LogEntry)

    /// Flush any pending writes
    func flush()
}

// MARK: - Hashable Conformance

extension LogDestination {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
