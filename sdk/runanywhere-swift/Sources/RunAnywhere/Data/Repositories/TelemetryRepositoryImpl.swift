import Foundation
import GRDB

/// Repository for managing telemetry data
public actor TelemetryRepositoryImpl: Repository, TelemetryRepository {
    public typealias Entity = TelemetryData

    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "TelemetryRepository")
    private let batchSize = SDKConstants.TelemetryDefaults.batchSize

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: TelemetryData) async throws {
        let record = try mapToRecord(entity)

        try databaseManager.write { db in
            try record.save(db)
        }

        // Check if we should auto-sync
        let pendingCount = try await getPendingCount()
        if pendingCount >= batchSize {
            Task {
                try? await sync()
            }
        }
    }

    public func fetch(id: String) async throws -> TelemetryData? {
        let record = try databaseManager.read { db in
            try TelemetryRecord.fetchOne(db, key: id)
        }

        return record.map(mapToEntity)
    }

    public func fetchAll() async throws -> [TelemetryData] {
        let records = try databaseManager.read { db in
            try TelemetryRecord
                .order(TelemetryRecord.Columns.timestamp.desc)
                .fetchAll(db)
        }

        return records.map(mapToEntity)
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try TelemetryRecord.deleteOne(db, key: id)
        }
    }

    public func fetchPendingSync() async throws -> [TelemetryData] {
        let records = try databaseManager.read { db in
            try TelemetryRecord
                .filter(TelemetryRecord.Columns.syncPending == true)
                .limit(batchSize)
                .fetchAll(db)
        }

        return records.map(mapToEntity)
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try TelemetryRecord.fetchOne(db, key: id) {
                    record.syncPending = false
                    try record.update(db)
                }
            }
        }
    }

    public func sync() async throws {
        guard let apiClient = apiClient else {
            logger.warning("API client not available for sync")
            return
        }

        let pending = try await fetchPendingSync()
        guard !pending.isEmpty else {
            return
        }

        logger.info("Syncing \(pending.count) telemetry events")

        // For v1, just mark as synced - actual API call would be implemented later
        let ids = pending.map { $0.id }
        try await markSynced(ids)
    }

    // MARK: - Helper Methods

    private func getPendingCount() async throws -> Int {
        let count = try databaseManager.read { db in
            try TelemetryRecord
                .filter(TelemetryRecord.Columns.syncPending == true)
                .fetchCount(db)
        }

        return count
    }

    /// Track an event
    public func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws {
        let event = TelemetryData(
            eventType: type.rawValue,
            properties: properties
        )

        try await save(event)
    }

    // MARK: - TelemetryRepository Protocol Methods

    public func fetchByDateRange(from: Date, to: Date) async throws -> [TelemetryData] {
        let records = try databaseManager.read { db in
            try TelemetryRecord
                .filter(TelemetryRecord.Columns.timestamp >= from)
                .filter(TelemetryRecord.Columns.timestamp <= to)
                .order(TelemetryRecord.Columns.timestamp.desc)
                .fetchAll(db)
        }

        return records.map(mapToEntity)
    }

    public func fetchUnsent() async throws -> [TelemetryData] {
        let records = try databaseManager.read { db in
            try TelemetryRecord
                .filter(TelemetryRecord.Columns.syncPending == true)
                .order(TelemetryRecord.Columns.timestamp.desc)
                .fetchAll(db)
        }

        return records.map(mapToEntity)
    }

    public func markAsSent(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try TelemetryRecord.fetchOne(db, key: id) {
                    record.syncPending = false
                    try record.update(db)
                }
            }
        }

        logger.info("Marked \(ids.count) telemetry events as sent")
    }

    public func cleanup(olderThan date: Date) async throws {
        let deletedCount = try databaseManager.write { db in
            try TelemetryRecord
                .filter(TelemetryRecord.Columns.timestamp < date)
                .deleteAll(db)
        }

        logger.info("Cleaned up \(deletedCount) telemetry events older than \(date)")
    }

    // MARK: - Mapping Functions

    private func mapToRecord(_ entity: TelemetryData) throws -> TelemetryRecord {
        // Convert properties to JSON
        let propertiesData: Data?
        if !entity.properties.isEmpty {
            propertiesData = try JSONSerialization.data(withJSONObject: entity.properties)
        } else {
            propertiesData = nil
        }

        // Extract event name from eventType (e.g., "model.loaded" -> "loaded")
        let eventName = entity.eventType.components(separatedBy: ".").last ?? entity.eventType

        // Get SDK version
        let sdkVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? SDKConstants.DatabaseDefaults.sdkVersion

        return TelemetryRecord(
            id: entity.id,
            eventType: entity.eventType,
            eventName: eventName,
            properties: propertiesData,
            userId: nil, // Could be added to TelemetryData if needed
            sessionId: nil, // Could be linked to generation sessions
            deviceInfo: nil, // Could be populated with device details
            sdkVersion: sdkVersion,
            timestamp: entity.timestamp,
            createdAt: entity.timestamp,
            syncPending: entity.syncPending
        )
    }

    private func mapToEntity(_ record: TelemetryRecord) -> TelemetryData {
        // Parse properties JSON
        var properties: [String: String] = [:]
        if let propertiesData = record.properties,
           let json = try? JSONSerialization.jsonObject(with: propertiesData) as? [String: Any] {
            // Convert all values to strings for TelemetryData compatibility
            properties = json.compactMapValues { value in
                switch value {
                case let string as String:
                    return string
                case let number as NSNumber:
                    return number.stringValue
                default:
                    return String(describing: value)
                }
            }
        }

        return TelemetryData(
            id: record.id,
            eventType: record.eventType,
            properties: properties,
            timestamp: record.timestamp,
            updatedAt: record.createdAt,
            syncPending: record.syncPending
        )
    }
}
