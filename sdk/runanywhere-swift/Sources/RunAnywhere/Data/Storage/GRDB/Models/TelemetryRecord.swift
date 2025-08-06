import Foundation
import GRDB

/// GRDB record for telemetry table
struct TelemetryRecord: Codable {
    var id: String
    var eventType: String
    var eventName: String
    var properties: Data? // JSON blob
    var userId: String?
    var sessionId: String?
    var deviceInfo: Data? // JSON blob
    var sdkVersion: String
    var timestamp: Date
    var createdAt: Date
    var syncPending: Bool

    init(
        id: String = UUID().uuidString,
        eventType: String,
        eventName: String,
        properties: Data? = nil,
        userId: String? = nil,
        sessionId: String? = nil,
        deviceInfo: Data? = nil,
        sdkVersion: String = SDKConstants.DatabaseDefaults.sdkVersion,
        timestamp: Date = Date(),
        createdAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.eventType = eventType
        self.eventName = eventName
        self.properties = properties
        self.userId = userId
        self.sessionId = sessionId
        self.deviceInfo = deviceInfo
        self.sdkVersion = sdkVersion
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.syncPending = syncPending
    }
}

// MARK: - TableRecord
extension TelemetryRecord: TableRecord {
    static let databaseTableName = "telemetry"
}

// MARK: - FetchableRecord
extension TelemetryRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension TelemetryRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension TelemetryRecord {
    enum Columns: String, ColumnExpression {
        case id
        case eventType = "event_type"
        case eventName = "event_name"
        case properties
        case userId = "user_id"
        case sessionId = "session_id"
        case deviceInfo = "device_info"
        case sdkVersion = "sdk_version"
        case timestamp
        case createdAt = "created_at"
        case syncPending = "sync_pending"
    }
}
