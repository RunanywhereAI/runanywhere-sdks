import Foundation
import GRDB

/// Repository for managing telemetry data - minimal implementation
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
        var entityToSave = entity
        _ = entityToSave.markUpdated()

        try databaseManager.write { db in
            try entityToSave.save(db)
        }

        logger.debug("Saved telemetry event: \(entity.id)")
    }

    public func fetch(id: String) async throws -> TelemetryData? {
        return try databaseManager.read { db in
            try TelemetryData.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try TelemetryData.deleteOne(db, key: id)
        }
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .filter(Column("syncPending") == true)
                .limit(batchSize)
                .fetchAll(db)
        }
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try TelemetryData.fetchOne(db, key: id) {
                    _ = data.markSynced()
                    try data.update(db)
                }
            }
        }
        logger.debug("Marked \(ids.count) telemetry events as synced")
    }

    // MARK: - TelemetryRepository Protocol Methods

    /// Track an event
    public func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws {
        let event = TelemetryData(
            eventType: type.rawValue,
            properties: properties
        )

        try await save(event)
    }

    public func fetchByDateRange(from: Date, to: Date) async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .filter(Column("timestamp") >= from)
                .filter(Column("timestamp") <= to)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    public func fetchUnsent() async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .filter(Column("syncPending") == true)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    public func markAsSent(_ ids: [String]) async throws {
        try await markSynced(ids)
        logger.info("Marked \(ids.count) telemetry events as sent")
    }

    public func cleanup(olderThan date: Date) async throws {
        let deletedCount = try databaseManager.write { db in
            try TelemetryData
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }

        logger.info("Cleaned up \(deletedCount) telemetry events older than \(date)")
    }
}
