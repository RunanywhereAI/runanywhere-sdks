//
//  LogEntry.swift
//  RunAnywhere SDK
//
//  Single log entry structure
//

import Foundation

/// Log entry structure
internal struct LogEntry: Encodable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let metadata: [String: String]?
    let deviceInfo: DeviceInfo?

    init(timestamp: Date, level: LogLevel, category: String, message: String, metadata: [String: Any]?, deviceInfo: DeviceInfo? = nil) {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level.description, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        if let metadata = metadata {
            try container.encode(metadata, forKey: .metadata)
        }
        // Include deviceInfo if present (it's already Codable)
        if let deviceInfo = deviceInfo {
            try container.encode(deviceInfo, forKey: .deviceInfo)
        }
    }
}
