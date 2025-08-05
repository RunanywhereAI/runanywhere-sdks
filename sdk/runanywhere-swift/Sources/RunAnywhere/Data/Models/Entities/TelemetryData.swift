import Foundation

/// Persisted telemetry event data
public struct TelemetryData: RepositoryEntity {
    public let id: String
    public let eventType: String
    public let properties: [String: String]
    public let timestamp: Date
    public let updatedAt: Date
    public let syncPending: Bool

    public init(
        id: String = UUID().uuidString,
        eventType: String,
        properties: [String: String],
        timestamp: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.eventType = eventType
        self.properties = properties
        self.timestamp = timestamp
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }
}
