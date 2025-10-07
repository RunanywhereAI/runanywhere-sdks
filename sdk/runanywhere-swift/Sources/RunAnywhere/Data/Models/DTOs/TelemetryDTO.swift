import Foundation

/// Data Transfer Object for telemetry submission
public struct TelemetryDTO: Codable {
    public let events: [TelemetryEventDTO]
    public let deviceId: String
    public let sessionId: String
    public let timestamp: Date

    public init(
        events: [TelemetryEventDTO],
        deviceId: String,
        sessionId: String,
        timestamp: Date = Date()
    ) {
        self.events = events
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}

/// Telemetry event type
public enum TelemetryEventType: String, Codable {
    case modelLoaded = "model_loaded"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case error = "error"
    case performance = "performance"
    case memory = "memory"
    case custom = "custom"
}

/// Individual telemetry event
public struct TelemetryEventDTO: Codable {
    public let id: String
    public let type: TelemetryEventType
    public let data: [String: Any]
    public let timestamp: Date

    // Custom encoding/decoding for [String: Any]
    private enum CodingKeys: String, CodingKey {
        case id, type, data, timestamp
    }

    public init(
        id: String,
        type: TelemetryEventType,
        data: [String: Any],
        timestamp: Date
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(TelemetryEventType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        if let dataData = try container.decodeIfPresent(Data.self, forKey: .data) {
            data = try JSONSerialization.jsonObject(with: dataData) as? [String: Any] ?? [:]
        } else {
            data = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)

        let dataData = try JSONSerialization.data(withJSONObject: data)
        try container.encode(dataData, forKey: .data)
    }
}

/// Response from telemetry submission
public struct TelemetrySubmissionResponse: Codable {
    public let accepted: Int
    public let rejected: Int
    public let errors: [String]?
}
