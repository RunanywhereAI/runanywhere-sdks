import Foundation
import GRDB

/// Local data source for managing model information in database
public actor LocalModelInfoDataSource: LocalDataSource {
    public typealias Entity = ModelInfo

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "LocalModelInfoDataSource")

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        do {
            _ = try databaseManager.read { db in
                try db.tableExists("models")
            }
            return true
        } catch {
            logger.debug("Database table 'models' not available: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard await isAvailable() else {
            throw DataSourceError.storageUnavailable
        }
    }

    // MARK: - LocalDataSource Protocol

    public func load(id: String) async throws -> ModelInfo? {
        logger.debug("Loading model: \(id)")

        return try databaseManager.read { db in
            try ModelInfo.fetchOne(db, key: id)
        }
    }

    public func loadAll() async throws -> [ModelInfo] {
        logger.debug("Loading all models")

        // Ensure table exists before loading
        try await ensureModelsTableExists()

        let data = try databaseManager.read { db in
            try ModelInfo
                .order(ModelInfo.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        logger.info("Found \(data.count) models in database")
        return data
    }

    public func store(_ entity: ModelInfo) async throws {
        logger.debug("Storing model: \(entity.id)")

        // Ensure table exists before storing
        try await ensureModelsTableExists()

        var entityToSave = entity
        entityToSave.markUpdated()

        try databaseManager.write { db in
            try entityToSave.save(db)
        }

        logger.info("Model stored successfully: \(entity.id)")
    }

    public func remove(id: String) async throws {
        logger.debug("Removing model: \(id)")

        let deleted = try databaseManager.write { db in
            try ModelInfo.deleteOne(db, key: id)
        }

        if deleted {
            logger.info("Model removed successfully: \(id)")
        } else {
            logger.debug("Model not found for removal: \(id)")
        }
    }

    public func clear() async throws {
        logger.debug("Clearing all models")

        let deletedCount = try databaseManager.write { db in
            try ModelInfo.deleteAll(db)
        }

        logger.info("Cleared \(deletedCount) model entries")
    }

    public func getStorageInfo() async throws -> DataSourceStorageInfo {
        let entityCount = try databaseManager.read { db in
            try ModelInfo.fetchCount(db)
        }

        return DataSourceStorageInfo(
            entityCount: entityCount,
            lastUpdated: Date()
        )
    }

    // MARK: - Model-specific methods

    /// Find models by framework
    public func findByFramework(_ framework: LLMFramework) async throws -> [ModelInfo] {
        return try databaseManager.read { db in
            try ModelInfo
                .filter(sql: "compatibleFrameworks LIKE ?", arguments: ["%\"\(framework.rawValue)\"%"])
                .order(ModelInfo.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Find models by category
    public func findByCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        return try databaseManager.read { db in
            try ModelInfo
                .filter(ModelInfo.Columns.category == category.rawValue)
                .order(ModelInfo.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Find downloaded models
    public func findDownloaded() async throws -> [ModelInfo] {
        return try databaseManager.read { db in
            try ModelInfo
                .filter(ModelInfo.Columns.localPath != nil)
                .order(ModelInfo.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Load models that need sync
    public func loadPendingSync() async throws -> [ModelInfo] {
        return try databaseManager.read { db in
            try ModelInfo
                .filter(ModelInfo.Columns.syncPending == true)
                .fetchAll(db)
        }
    }

    /// Mark models as synced
    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try ModelInfo.fetchOne(db, key: id) {
                    data.markSynced()
                    try data.update(db)
                }
            }
        }
    }

    /// Update download status
    public func updateDownloadStatus(_ modelId: String, localPath: URL?) async throws {
        try databaseManager.write { db in
            if var model = try ModelInfo.fetchOne(db, key: modelId) {
                model.localPath = localPath
                model.markUpdated()
                try model.update(db)
            }
        }
    }

    /// Update last used
    public func updateLastUsed(_ modelId: String) async throws {
        try databaseManager.write { db in
            if var model = try ModelInfo.fetchOne(db, key: modelId) {
                model.lastUsed = Date()
                model.usageCount += 1
                model.markUpdated()
                try model.update(db)
            }
        }
    }

    // MARK: - Table Management

    /// Ensure the models table exists, creating it if necessary
    private func ensureModelsTableExists() async throws {
        let tableExists = try databaseManager.read { db in
            try db.tableExists("models")
        }

        if !tableExists {
            logger.info("Models table doesn't exist, creating it...")
            try databaseManager.write { db in
                // swiftlint:disable:next identifier_name
                try db.create(table: "models", ifNotExists: true) { t in
                    t.primaryKey("id", .text)
                    t.column("name", .text).notNull()
                    t.column("category", .text).notNull()

                    // Format and location
                    t.column("format", .text).notNull()
                    t.column("downloadURL", .text)
                    t.column("localPath", .text)

                    // Size information
                    t.column("downloadSize", .integer)
                    t.column("memoryRequired", .integer)

                    // Framework compatibility
                    t.column("compatibleFrameworks", .blob).notNull()
                    t.column("preferredFramework", .text)

                    // Model-specific capabilities
                    t.column("contextLength", .integer)
                    t.column("supportsThinking", .boolean).notNull().defaults(to: false)

                    // Metadata
                    t.column("metadata", .blob)

                    // Tracking fields
                    t.column("source", .text).notNull().defaults(to: "remote")
                    t.column("createdAt", .datetime).notNull()
                    t.column("updatedAt", .datetime).notNull()
                    t.column("syncPending", .boolean).notNull().defaults(to: false)

                    // Usage tracking
                    t.column("lastUsed", .datetime)
                    t.column("usageCount", .integer).notNull().defaults(to: 0)
                }
            }
            logger.info("✅ Models table created successfully")
        }
    }
}
