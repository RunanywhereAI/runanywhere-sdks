import Foundation

/// Repository for managing telemetry data
public actor TelemetryRepository: Repository {
    public typealias Entity = TelemetryData

    private let database: DatabaseCore
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "TelemetryRepository")
    private let tableName = "telemetry"
    private let batchSize = 50

    // MARK: - Initialization

    public init(database: DatabaseCore, apiClient: APIClient?) {
        self.database = database
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: TelemetryData) async throws {
        let data = try JSONEncoder().encode(entity)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            INSERT OR REPLACE INTO \(tableName) (id, data, updated_at, sync_pending)
            VALUES (?, ?, ?, ?)
        """, parameters: [entity.id, json, entity.updatedAt, entity.syncPending ? 1 : 0])

        // Check if we should auto-sync
        let pendingCount = try await getPendingCount()
        if pendingCount >= batchSize {
            Task {
                try? await sync()
            }
        }
    }

    public func fetch(id: String) async throws -> TelemetryData? {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE id = ?
        """, parameters: [id])

        guard let row = results.first,
              let json = row["data"] as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(TelemetryData.self, from: data)
    }

    public func fetchAll() async throws -> [TelemetryData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) ORDER BY updated_at DESC
        """, parameters: [])

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode(TelemetryData.self, from: data)
        }
    }

    public func delete(id: String) async throws {
        try await database.execute("""
            DELETE FROM \(tableName) WHERE id = ?
        """, parameters: [id])
    }

    public func fetchPendingSync() async throws -> [TelemetryData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE sync_pending = 1 LIMIT ?
        """, parameters: [batchSize])

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode(TelemetryData.self, from: data)
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
        let results = try await database.query("""
            SELECT COUNT(*) as count FROM \(tableName) WHERE sync_pending = 1
        """, parameters: [])

        guard let row = results.first,
              let count = row["count"] as? Int64 else {
            return 0
        }

        return Int(count)
    }

    /// Track an event
    public func trackEvent(_ type: String, properties: [String: String]) async throws {
        let event = TelemetryData(
            eventType: type,
            properties: properties
        )

        try await save(event)
    }
}
