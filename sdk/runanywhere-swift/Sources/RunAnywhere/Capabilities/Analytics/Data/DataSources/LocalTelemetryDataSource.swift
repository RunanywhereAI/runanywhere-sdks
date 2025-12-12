import Foundation
import GRDB

/// Local data source for managing telemetry data in database
public actor LocalTelemetryDataSource: LocalDataSource {
    public typealias Entity = TelemetryData

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "LocalTelemetryDataSource")
    private let batchSize = AnalyticsConstants.telemetryBatchSize

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        do {
            _ = try databaseManager.read { db in
                try db.tableExists("telemetry")
            }
            return true
        } catch {
            logger.debug("Database table 'telemetry' not available: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard await isAvailable() else {
            throw DataSourceError.storageUnavailable
        }
    }

    // MARK: - LocalDataSource Protocol

    public func load(id: String) async throws -> TelemetryData? {
        logger.debug("Loading telemetry event: \(id)")

        return try databaseManager.read { db in
            try TelemetryData.fetchOne(db, key: id)
        }
    }

    public func loadAll() async throws -> [TelemetryData] {
        logger.debug("Loading all telemetry events")

        return try databaseManager.read { db in
            try TelemetryData
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    public func store(_ entity: TelemetryData) async throws {
        logger.debug("Storing telemetry event: \(entity.id)")

        var entityToSave = entity
        _ = entityToSave.markUpdated()

        try databaseManager.write { db in
            try entityToSave.save(db)
        }

        logger.debug("Telemetry event stored successfully: \(entity.id)")
    }

    public func remove(id: String) async throws {
        logger.debug("Removing telemetry event: \(id)")

        let deleted = try databaseManager.write { db in
            try TelemetryData.deleteOne(db, key: id)
        }

        if deleted {
            logger.debug("Telemetry event removed successfully: \(id)")
        } else {
            logger.debug("Telemetry event not found for removal: \(id)")
        }
    }

    public func clear() async throws {
        logger.debug("Clearing all telemetry events")

        let deletedCount = try databaseManager.write { db in
            try TelemetryData.deleteAll(db)
        }

        logger.info("Cleared \(deletedCount) telemetry events")
    }

    public func getStorageInfo() async throws -> DataSourceStorageInfo {
        let entityCount = try databaseManager.read { db in
            try TelemetryData.fetchCount(db)
        }

        return DataSourceStorageInfo(
            entityCount: entityCount,
            lastUpdated: Date()
        )
    }

    // MARK: - Telemetry-specific methods

    /// Load pending sync events
    public func loadPendingSync() async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .filter(Column("syncPending") == true)
                .limit(batchSize)
                .fetchAll(db)
        }
    }

    /// Mark events as synced
    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try TelemetryData.fetchOne(db, key: id) {
                    _ = data.markSynced()
                    try data.update(db)
                }
            }
        }
    }

    /// Load events by type
    public func loadByType(_ type: TelemetryEventType) async throws -> [TelemetryData] {
        return try databaseManager.read { db in
            try TelemetryData
                .filter(Column("eventType") == type.rawValue)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Delete old events beyond retention period
    public func deleteOldEvents(before date: Date) async throws {
        let deletedCount = try databaseManager.write { db in
            try TelemetryData
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }

        logger.info("Deleted \(deletedCount) old telemetry events")
    }
}
