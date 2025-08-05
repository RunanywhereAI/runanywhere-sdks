import Foundation

/// Repository for managing SDK configuration data
public actor ConfigurationRepositoryImpl: Repository, ConfigurationRepository {
    public typealias Entity = ConfigurationData

    private let database: DatabaseCore
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ConfigurationRepository")
    private let tableName = "configuration"

    // MARK: - Initialization

    public init(database: DatabaseCore, apiClient: APIClient?) {
        self.database = database
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: ConfigurationData) async throws {
        let data = try JSONEncoder().encode(entity)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            INSERT OR REPLACE INTO \(tableName) (id, data, updated_at, sync_pending)
            VALUES (?, ?, ?, ?)
        """, parameters: [entity.id, json, entity.updatedAt, entity.syncPending ? 1 : 0])

        logger.info("Configuration saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ConfigurationData? {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE id = ?
        """, parameters: [id])

        guard let row = results.first,
              let json = row["data"] as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(ConfigurationData.self, from: data)
    }

    public func fetchAll() async throws -> [ConfigurationData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) ORDER BY updated_at DESC
        """, parameters: [])

        logger.info("Found \(results.count) configurations in database")

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                logger.warning("Failed to parse configuration data")
                return nil
            }

            do {
                let config = try JSONDecoder().decode(ConfigurationData.self, from: data)
                logger.info("Fetched config - id: \(config.id)")
                return config
            } catch {
                logger.error("Failed to decode configuration: \(error)")
                return nil
            }
        }
    }

    public func delete(id: String) async throws {
        try await database.execute("""
            DELETE FROM \(tableName) WHERE id = ?
        """, parameters: [id])

        logger.info("Configuration deleted: \(id)")
    }

    public func fetchPendingSync() async throws -> [ConfigurationData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE sync_pending = 1
        """, parameters: [])

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode(ConfigurationData.self, from: data)
        }
    }

    public func markSynced(_ ids: [String]) async throws {
        try await database.transaction { db in
            for id in ids {
                try await db.execute("""
                    UPDATE \(self.tableName) SET sync_pending = 0 WHERE id = ?
                """, parameters: [id])
            }
        }

        logger.info("Marked \(ids.count) configurations as synced")
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

        // For now, just log - actual sync would be implemented later
        logger.info("Would sync \(pending.count) configurations")

        // Example sync implementation:
        // let response = try await apiClient.post(.syncConfiguration, pending)
        // try await markSynced(response.syncedIds)
    }

    // MARK: - ConfigurationRepository Protocol Methods

    public func fetchByKey(_ key: String) async throws -> ConfigurationData? {
        // For now, just return the default configuration if key matches
        if key == "default" {
            return try await fetch("default")
        }
        return nil
    }

    public func updatePartial(_ id: String, updates: (ConfigurationData) -> ConfigurationData) async throws {
        guard let existing = try await fetch(id) else {
            throw RepositoryError.entityNotFound(id: id)
        }

        let updated = updates(existing)
        try await save(updated.markUpdated())
    }
}
