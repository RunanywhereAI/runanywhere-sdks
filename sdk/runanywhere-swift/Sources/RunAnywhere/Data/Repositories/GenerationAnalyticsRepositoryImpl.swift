import Foundation

/// Implementation of generation analytics repository for persistence
public actor GenerationAnalyticsRepositoryImpl: GenerationAnalyticsRepository {
    // MARK: - Properties

    private let database: DatabaseCore
    private let syncService: DataSyncService?
    private let logger = SDKLogger(category: "GenerationAnalyticsRepository")

    // Table names
    private let sessionsTable = "generation_sessions"
    private let generationsTable = "generations"

    // MARK: - Initialization

    public init(database: DatabaseCore, syncService: DataSyncService?) {
        self.database = database
        self.syncService = syncService

        Task {
            await createTablesIfNeeded()
        }
    }

    // MARK: - Session Operations

    public func saveSession(_ session: GenerationSession) async throws {
        let data = try JSONEncoder().encode(session)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            INSERT OR REPLACE INTO \(sessionsTable)
            (id, model_id, session_type, data, created_at, updated_at, sync_pending)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, parameters: [
            session.id.uuidString,
            session.modelId,
            session.sessionType.rawValue,
            json,
            session.startTime,
            Date(),
            1
        ])

        logger.debug("Saved session: \(session.id)")
    }

    public func updateSession(_ session: GenerationSession) async throws {
        let data = try JSONEncoder().encode(session)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            UPDATE \(sessionsTable)
            SET data = ?, updated_at = ?, sync_pending = 1
            WHERE id = ?
        """, parameters: [
            json,
            Date(),
            session.id.uuidString
        ])

        logger.debug("Updated session: \(session.id)")
    }

    public func getSession(_ id: UUID) async throws -> GenerationSession? {
        let results = try await database.query("""
            SELECT data FROM \(sessionsTable) WHERE id = ?
        """, parameters: [id.uuidString])

        guard let row = results.first,
              let jsonString = row["data"] as? String,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(GenerationSession.self, from: data)
    }

    public func getAllSessions() async throws -> [GenerationSession] {
        let results = try await database.query("""
            SELECT data FROM \(sessionsTable) ORDER BY created_at DESC
        """, parameters: [])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(GenerationSession.self, from: data)
        }
    }

    public func getActiveSessions() async throws -> [GenerationSession] {
        let results = try await database.query("""
            SELECT data FROM \(sessionsTable)
            WHERE json_extract(data, '$.endTime') IS NULL
            ORDER BY created_at DESC
        """, parameters: [])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(GenerationSession.self, from: data)
        }
    }

    public func deleteSession(_ id: UUID) async throws {
        try await database.execute("""
            DELETE FROM \(sessionsTable) WHERE id = ?
        """, parameters: [id.uuidString])

        // Also delete associated generations
        try await database.execute("""
            DELETE FROM \(generationsTable) WHERE session_id = ?
        """, parameters: [id.uuidString])

        logger.debug("Deleted session and generations: \(id)")
    }

    // MARK: - Generation Operations

    public func saveGeneration(_ generation: Generation) async throws {
        let data = try JSONEncoder().encode(generation)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            INSERT OR REPLACE INTO \(generationsTable)
            (id, session_id, sequence_number, data, created_at, updated_at, sync_pending)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, parameters: [
            generation.id.uuidString,
            generation.sessionId.uuidString,
            generation.sequenceNumber,
            json,
            generation.timestamp,
            Date(),
            1
        ])

        logger.debug("Saved generation: \(generation.id)")
    }

    public func updateGeneration(_ generation: Generation) async throws {
        let data = try JSONEncoder().encode(generation)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            UPDATE \(generationsTable)
            SET data = ?, updated_at = ?, sync_pending = 1
            WHERE id = ?
        """, parameters: [
            json,
            Date(),
            generation.id.uuidString
        ])

        logger.debug("Updated generation: \(generation.id)")
    }

    public func getGeneration(_ id: UUID) async throws -> Generation? {
        let results = try await database.query("""
            SELECT data FROM \(generationsTable) WHERE id = ?
        """, parameters: [id.uuidString])

        guard let row = results.first,
              let jsonString = row["data"] as? String,
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(Generation.self, from: data)
    }

    public func getGenerations(sessionId: UUID) async throws -> [Generation] {
        let results = try await database.query("""
            SELECT data FROM \(generationsTable)
            WHERE session_id = ?
            ORDER BY sequence_number ASC
        """, parameters: [sessionId.uuidString])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(Generation.self, from: data)
        }
    }

    public func deleteGeneration(_ id: UUID) async throws {
        try await database.execute("""
            DELETE FROM \(generationsTable) WHERE id = ?
        """, parameters: [id.uuidString])

        logger.debug("Deleted generation: \(id)")
    }

    // MARK: - Analytics Queries

    public func getSessionsByModel(_ modelId: String, limit: Int) async throws -> [GenerationSession] {
        let results = try await database.query("""
            SELECT data FROM \(sessionsTable)
            WHERE model_id = ?
            ORDER BY created_at DESC
            LIMIT ?
        """, parameters: [modelId, limit])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(GenerationSession.self, from: data)
        }
    }

    public func getRecentGenerations(limit: Int) async throws -> [Generation] {
        let results = try await database.query("""
            SELECT data FROM \(generationsTable)
            ORDER BY created_at DESC
            LIMIT ?
        """, parameters: [limit])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(Generation.self, from: data)
        }
    }

    // MARK: - Sync Operations

    public func getPendingSyncSessions() async throws -> [GenerationSession] {
        let results = try await database.query("""
            SELECT data FROM \(sessionsTable)
            WHERE sync_pending = 1
            ORDER BY created_at ASC
        """, parameters: [])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(GenerationSession.self, from: data)
        }
    }

    public func getPendingSyncGenerations() async throws -> [Generation] {
        let results = try await database.query("""
            SELECT data FROM \(generationsTable)
            WHERE sync_pending = 1
            ORDER BY created_at ASC
        """, parameters: [])

        return results.compactMap { row in
            guard let jsonString = row["data"] as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(Generation.self, from: data)
        }
    }

    public func markSessionsSynced(_ ids: [UUID]) async throws {
        for id in ids {
            try await database.execute("""
                UPDATE \(sessionsTable)
                SET sync_pending = 0
                WHERE id = ?
            """, parameters: [id.uuidString])
        }

        logger.debug("Marked \(ids.count) sessions as synced")
    }

    public func markGenerationsSynced(_ ids: [UUID]) async throws {
        for id in ids {
            try await database.execute("""
                UPDATE \(generationsTable)
                SET sync_pending = 0
                WHERE id = ?
            """, parameters: [id.uuidString])
        }

        logger.debug("Marked \(ids.count) generations as synced")
    }

    // MARK: - Private Methods

    private func createTablesIfNeeded() async {
        do {
            // Create sessions table
            try await database.execute("""
                CREATE TABLE IF NOT EXISTS \(sessionsTable) (
                    id TEXT PRIMARY KEY,
                    model_id TEXT NOT NULL,
                    session_type TEXT NOT NULL,
                    data TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    sync_pending INTEGER DEFAULT 1
                )
            """, parameters: [])

            // Create generations table
            try await database.execute("""
                CREATE TABLE IF NOT EXISTS \(generationsTable) (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    sequence_number INTEGER NOT NULL,
                    data TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    sync_pending INTEGER DEFAULT 1,
                    FOREIGN KEY (session_id) REFERENCES \(sessionsTable)(id)
                )
            """, parameters: [])

            // Create indexes
            try await database.execute("""
                CREATE INDEX IF NOT EXISTS idx_sessions_model_id
                ON \(sessionsTable)(model_id)
            """, parameters: [])

            try await database.execute("""
                CREATE INDEX IF NOT EXISTS idx_generations_session_id
                ON \(generationsTable)(session_id)
            """, parameters: [])

            logger.info("Analytics tables created/verified")
        } catch {
            logger.error("Failed to create tables: \(error)")
        }
    }
}
