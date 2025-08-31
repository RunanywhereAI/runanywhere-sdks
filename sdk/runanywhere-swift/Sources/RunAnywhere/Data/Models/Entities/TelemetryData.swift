import Foundation
import GRDB

/// Persisted telemetry event data
public struct TelemetryData: Codable, RepositoryEntity, FetchableRecord, PersistableRecord {
    public let id: String
    public let eventType: String
    public let properties: [String: String]
    public let timestamp: Date
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    public init(
        id: String = UUID().uuidString,
        eventType: String,
        properties: [String: String] = [:],
        timestamp: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.eventType = eventType
        self.properties = properties
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

    // MARK: - Syncable

    public mutating func markUpdated() -> Self {
        self.updatedAt = Date()
        self.syncPending = true
        return self
    }

    public mutating func markSynced() -> Self {
        self.syncPending = false
        return self
    }

    // MARK: - GRDB

    public static var databaseTableName: String { "telemetry" }
}
