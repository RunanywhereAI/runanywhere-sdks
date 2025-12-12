//
//  LogEntry.swift
//  RunAnywhere SDK
//
//  Single log entry structure
//

import Foundation

/// Log entry structure representing a single log message
public struct LogEntry: Encodable, Sendable {
    /// Timestamp when the log was created
    public let timestamp: Date

    /// Severity level of the log
    public let level: LogLevel

    /// Category/subsystem for the log
    public let category: String

    /// The log message
    public let message: String

    /// Optional metadata (converted to strings for Codable conformance)
    public let metadata: [String: String]?

    /// Optional device information
    public let deviceInfo: DeviceInfo?

    /// Initialize a log entry
    /// - Parameters:
    ///   - timestamp: When the log was created
    ///   - level: Severity level
    ///   - category: Category/subsystem
    ///   - message: Log message
    ///   - metadata: Optional additional context
    ///   - deviceInfo: Optional device information
    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public init(timestamp: Date, level: LogLevel, category: String, message: String, metadata: [String: Any]?, deviceInfo: DeviceInfo? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata?.mapValues { String(describing: $0) }
        self.deviceInfo = deviceInfo
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, level, category, message, metadata, deviceInfo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level.description, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        if let metadata = metadata {
            try container.encode(metadata, forKey: .metadata)
        }
        if let deviceInfo = deviceInfo {
            try container.encode(deviceInfo, forKey: .deviceInfo)
        }
    }
}
