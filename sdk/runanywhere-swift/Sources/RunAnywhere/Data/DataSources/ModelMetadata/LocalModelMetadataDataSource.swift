import Foundation
import GRDB

/// Local data source for managing model metadata in database
public actor LocalModelMetadataDataSource: LocalDataSource {
    public typealias Entity = ModelMetadataData

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "LocalModelMetadataDataSource")

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        do {
            _ = try databaseManager.read { db in
                try db.tableExists("model_metadata")
            }
            return true
        } catch {
            logger.debug("Database table 'model_metadata' not available: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard await isAvailable() else {
            throw DataSourceError.storageUnavailable
        }
    }

    // MARK: - LocalDataSource Protocol

    public func load(id: String) async throws -> ModelMetadataData? {
        logger.debug("Loading model metadata: \(id)")

        return try databaseManager.read { db in
            try ModelMetadataData.fetchOne(db, key: id)
        }
    }

    public func loadAll() async throws -> [ModelMetadataData] {
        logger.debug("Loading all model metadata")

        let data = try databaseManager.read { db in
            try ModelMetadataData
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }

        logger.info("Found \(data.count) model metadata in database")
        return data
    }

    public func store(_ entity: ModelMetadataData) async throws {
        logger.debug("Storing model metadata: \(entity.id)")

        var entityToSave = entity
        _ = entityToSave.markUpdated()

        try databaseManager.write { db in
            try entityToSave.save(db)
        }

        logger.info("Model metadata stored successfully: \(entity.id)")
    }

    public func remove(id: String) async throws {
        logger.debug("Removing model metadata: \(id)")

        let deleted = try databaseManager.write { db in
            try ModelMetadataData.deleteOne(db, key: id)
        }

        if deleted {
            logger.info("Model metadata removed successfully: \(id)")
        } else {
            logger.debug("Model metadata not found for removal: \(id)")
        }
    }

    public func clear() async throws {
        logger.debug("Clearing all model metadata")

        let deletedCount = try databaseManager.write { db in
            try ModelMetadataData.deleteAll(db)
        }

        logger.info("Cleared \(deletedCount) model metadata entries")
    }

    public func getStorageInfo() async throws -> DataSourceStorageInfo {
        let entityCount = try databaseManager.read { db in
            try ModelMetadataData.fetchCount(db)
        }

        return DataSourceStorageInfo(
            entityCount: entityCount,
            lastUpdated: Date()
        )
    }

    // MARK: - Model Metadata-specific methods

    /// Find model by various criteria
    public func findModels(framework: String? = nil, format: String? = nil) async throws -> [ModelMetadataData] {
        return try databaseManager.read { db in
            var query = ModelMetadataData.all()

            if let framework = framework {
                query = query.filter(Column("framework") == framework)
            }

            if let format = format {
                query = query.filter(Column("format") == format)
            }

            return try query
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// Load models that need sync
    public func loadPendingSync() async throws -> [ModelMetadataData] {
        return try databaseManager.read { db in
            try ModelMetadataData
                .filter(Column("syncPending") == true)
                .fetchAll(db)
        }
    }

    /// Mark models as synced
    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try ModelMetadataData.fetchOne(db, key: id) {
                    _ = data.markSynced()
                    try data.update(db)
                }
            }
        }
    }

    /// Load models by status
    public func loadByStatus(_ status: String) async throws -> [ModelMetadataData] {
        return try databaseManager.read { db in
            try ModelMetadataData
                .filter(Column("status") == status)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }
}
