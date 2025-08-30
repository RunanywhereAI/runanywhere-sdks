import Foundation
import GRDB

/// Local data source for managing consumer configuration overrides in database
public actor LocalConfigurationDataSource: LocalDataSource {
    public typealias Entity = ConfigurationData

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "LocalConfigurationDataSource")

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        do {
            _ = try databaseManager.read { db in
                try db.tableExists("configuration")
            }
            return true
        } catch {
            logger.debug("Database table 'configuration' not available: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard await isAvailable() else {
            throw DataSourceError.storageUnavailable
        }
    }

    // MARK: - LocalDataSource Protocol

    public func load(id: String) async throws -> ConfigurationData? {
        logger.debug("Loading configuration: \(id)")

        let config = try databaseManager.read { db in
            try ConfigurationData.fetchOne(db, key: id)
        }

        if config == nil {
            logger.debug("Configuration not found: \(id)")
        }

        return config
    }

    public func loadAll() async throws -> [ConfigurationData] {
        logger.debug("Loading all configurations")

        return try databaseManager.read { db in
            try ConfigurationData.fetchAll(db)
        }
    }

    public func store(_ entity: ConfigurationData) async throws {
        logger.debug("Storing configuration: \(entity.id)")

        try databaseManager.write { db in
            try entity.save(db)
        }

        logger.debug("Configuration stored successfully: \(entity.id)")
    }

    public func remove(id: String) async throws {
        logger.debug("Removing configuration: \(id)")

        let deleted = try databaseManager.write { db in
            try ConfigurationData.deleteOne(db, key: id)
        }

        if deleted {
            logger.debug("Configuration removed successfully: \(id)")
        } else {
            logger.debug("Configuration not found for removal: \(id)")
        }
    }

    public func clear() async throws {
        logger.debug("Clearing all configurations")

        let deletedCount = try databaseManager.write { db in
            try ConfigurationData.deleteAll(db)
        }

        logger.info("Cleared \(deletedCount) configurations")
    }

    public func getStorageInfo() async throws -> DataSourceStorageInfo {
        let entityCount = try databaseManager.read { db in
            try ConfigurationData.fetchCount(db)
        }

        return DataSourceStorageInfo(
            totalSpace: nil, // Database doesn't provide this easily
            availableSpace: nil,
            usedSpace: nil,
            entityCount: entityCount,
            lastUpdated: Date()
        )
    }

    // MARK: - Configuration-specific methods

    /// Save consumer override configuration
    public func saveConsumerOverride(_ config: ConfigurationData) async throws {
        var consumerConfig = config
        consumerConfig.source = .consumer

        try databaseManager.write { db in
            // Delete any existing consumer override
            try ConfigurationData
                .filter(ConfigurationData.Columns.source == ConfigurationSource.consumer.rawValue)
                .deleteAll(db)

            // Save new consumer override
            try consumerConfig.save(db)
        }

        logger.info("Consumer override configuration saved")
    }

    /// Load consumer override configuration
    public func loadConsumerOverride() async throws -> ConfigurationData? {
        let config = try databaseManager.read { db in
            try ConfigurationData
                .filter(ConfigurationData.Columns.source == ConfigurationSource.consumer.rawValue)
                .fetchOne(db)
        }

        if config == nil {
            logger.debug("No consumer override configuration found")
        }

        return config
    }

    /// Delete consumer override configuration
    public func deleteConsumerOverride() async throws {
        try databaseManager.write { db in
            try ConfigurationData
                .filter(ConfigurationData.Columns.source == ConfigurationSource.consumer.rawValue)
                .deleteAll(db)
        }

        logger.info("Consumer override configuration deleted")
    }

    /// Load configuration from database
    public func loadConfiguration(id: String) async throws -> ConfigurationData? {
        return try await load(id: id)
    }

    /// Save configuration to database
    public func saveConfiguration(_ config: ConfigurationData) async throws {
        try await store(config)
    }
}
