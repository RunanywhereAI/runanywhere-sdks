import Foundation
import GRDB

/// Implementation of generation analytics repository for persistence
public actor GenerationAnalyticsRepositoryImpl: GenerationAnalyticsRepository {
    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private let syncService: DataSyncService?
    private let logger = SDKLogger(category: "GenerationAnalyticsRepository")

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, syncService: DataSyncService?) {
        self.databaseManager = databaseManager
        self.syncService = syncService
    }

    // MARK: - Session Operations

    public func saveSession(_ session: GenerationSession) async throws {
        let record = mapSessionToRecord(session)

        try databaseManager.write { db in
            try record.save(db)
        }

        logger.debug("Saved session: \(session.id)")
    }

    public func updateSession(_ session: GenerationSession) async throws {
        let record = mapSessionToRecord(session)

        try databaseManager.write { db in
            try record.update(db)
        }

        logger.debug("Updated session: \(session.id)")
    }

    public func getSession(_ id: UUID) async throws -> GenerationSession? {
        let record = try databaseManager.read { db in
            try GenerationSessionRecord.fetchOne(db, key: id.uuidString)
        }

        return record.map(mapRecordToSession)
    }

    public func getAllSessions() async throws -> [GenerationSession] {
        let records = try databaseManager.read { db in
            try GenerationSessionRecord
                .order(GenerationSessionRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }

        return records.map(mapRecordToSession)
    }

    public func getActiveSessions() async throws -> [GenerationSession] {
        let records = try databaseManager.read { db in
            try GenerationSessionRecord
                .filter(GenerationSessionRecord.Columns.endedAt == nil)
                .order(GenerationSessionRecord.Columns.createdAt.desc)
                .fetchAll(db)
        }

        return records.map(mapRecordToSession)
    }

    public func deleteSession(_ id: UUID) async throws {
        try databaseManager.write { db in
            // Delete session (generations will be cascade deleted due to foreign key)
            _ = try GenerationSessionRecord.deleteOne(db, key: id.uuidString)
        }

        logger.debug("Deleted session and generations: \(id)")
    }

    // MARK: - Generation Operations

    public func saveGeneration(_ generation: Generation) async throws {
        let record = mapGenerationToRecord(generation)

        try databaseManager.write { db in
            try record.save(db)
        }

        logger.debug("Saved generation: \(generation.id)")
    }

    public func updateGeneration(_ generation: Generation) async throws {
        let record = mapGenerationToRecord(generation)

        try databaseManager.write { db in
            try record.update(db)
        }

        logger.debug("Updated generation: \(generation.id)")
    }

    public func getGeneration(_ id: UUID) async throws -> Generation? {
        let record = try databaseManager.read { db in
            try GenerationRecord.fetchOne(db, key: id.uuidString)
        }

        return try record.map { try mapRecordToGeneration($0) }
    }

    public func getGenerations(sessionId: UUID) async throws -> [Generation] {
        let records = try databaseManager.read { db in
            try GenerationRecord
                .filter(GenerationRecord.Columns.generationSessionsId == sessionId.uuidString)
                .order(GenerationRecord.Columns.sequenceNumber.asc)
                .fetchAll(db)
        }

        return try records.map { try mapRecordToGeneration($0) }
    }

    public func deleteGeneration(_ id: UUID) async throws {
        try databaseManager.write { db in
            _ = try GenerationRecord.deleteOne(db, key: id.uuidString)
        }

        logger.debug("Deleted generation: \(id)")
    }

    // MARK: - Analytics Queries

    public func getSessionsByModel(_ modelId: String, limit: Int) async throws -> [GenerationSession] {
        let records = try databaseManager.read { db in
            try GenerationSessionRecord
                .filter(GenerationSessionRecord.Columns.modelMetadataId == modelId)
                .order(GenerationSessionRecord.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }

        return records.map(mapRecordToSession)
    }

    public func getRecentGenerations(limit: Int) async throws -> [Generation] {
        let records = try databaseManager.read { db in
            try GenerationRecord
                .order(GenerationRecord.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }

        return try records.map { try mapRecordToGeneration($0) }
    }

    // MARK: - Sync Operations

    public func getPendingSyncSessions() async throws -> [GenerationSession] {
        let records = try databaseManager.read { db in
            try GenerationSessionRecord
                .filter(GenerationSessionRecord.Columns.syncPending == true)
                .order(GenerationSessionRecord.Columns.createdAt.asc)
                .fetchAll(db)
        }

        return records.map(mapRecordToSession)
    }

    public func getPendingSyncGenerations() async throws -> [Generation] {
        let records = try databaseManager.read { db in
            try GenerationRecord
                .filter(GenerationRecord.Columns.syncPending == true)
                .order(GenerationRecord.Columns.createdAt.asc)
                .fetchAll(db)
        }

        return try records.map { try mapRecordToGeneration($0) }
    }

    public func markSessionsSynced(_ ids: [UUID]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try GenerationSessionRecord.fetchOne(db, key: id.uuidString) {
                    record.syncPending = false
                    record.updatedAt = Date()
                    try record.update(db)
                }
            }
        }

        logger.debug("Marked \(ids.count) sessions as synced")
    }

    public func markGenerationsSynced(_ ids: [UUID]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try GenerationRecord.fetchOne(db, key: id.uuidString) {
                    record.syncPending = false
                    try record.update(db)
                }
            }
        }

        logger.debug("Marked \(ids.count) generations as synced")
    }

    // MARK: - Mapping Functions

    private func mapSessionToRecord(_ session: GenerationSession) -> GenerationSessionRecord {
        // Create context data JSON
        let contextData: [String: Any] = [
            "generationCount": session.generationCount,
            "totalInputTokens": session.totalInputTokens,
            "totalOutputTokens": session.totalOutputTokens,
            "averageTimeToFirstToken": session.averageTimeToFirstToken,
            "averageTokensPerSecond": session.averageTokensPerSecond,
            "totalDuration": session.totalDuration
        ]

        let contextDataJSON = try? JSONSerialization.data(withJSONObject: contextData)

        return GenerationSessionRecord(
            id: session.id.uuidString,
            modelMetadataId: session.modelId,
            sessionType: session.sessionType.rawValue,
            totalTokens: session.totalInputTokens + session.totalOutputTokens,
            totalCost: 0.0, // Calculate based on model pricing
            messageCount: session.generationCount,
            contextData: contextDataJSON,
            startedAt: session.startTime,
            endedAt: session.endTime,
            createdAt: session.startTime,
            updatedAt: Date(),
            syncPending: true
        )
    }

    private func mapRecordToSession(_ record: GenerationSessionRecord) -> GenerationSession {
        var session = GenerationSession(
            id: UUID(uuidString: record.id) ?? UUID(),
            modelId: record.modelMetadataId,
            sessionType: SessionType(rawValue: record.sessionType) ?? .singleGeneration,
            startTime: record.startedAt,
            endTime: record.endedAt
        )

        // Parse context data if available
        if let contextData = record.contextData,
           let json = try? JSONSerialization.jsonObject(with: contextData) as? [String: Any] {
            session.generationCount = json["generationCount"] as? Int ?? 0
            session.totalInputTokens = json["totalInputTokens"] as? Int ?? 0
            session.totalOutputTokens = json["totalOutputTokens"] as? Int ?? 0
            session.averageTimeToFirstToken = json["averageTimeToFirstToken"] as? TimeInterval ?? 0
            session.averageTokensPerSecond = json["averageTokensPerSecond"] as? Double ?? 0
            session.totalDuration = json["totalDuration"] as? TimeInterval ?? 0
        }

        return session
    }

    private func mapGenerationToRecord(_ generation: Generation) throws -> GenerationRecord {
        // Serialize performance data
        let performanceData: Data?
        if let performance = generation.performance {
            performanceData = try JSONEncoder().encode(performance)
        } else {
            performanceData = nil
        }

        // Extract metrics from performance
        let promptTokens = generation.performance?.inputTokens ?? 0
        let completionTokens = generation.performance?.outputTokens ?? 0
        let latencyMs = (generation.performance?.totalDuration ?? 0) * 1000
        let tokensPerSecond = generation.performance?.tokensPerSecond ?? 0
        let timeToFirstTokenMs = (generation.performance?.timeToFirstToken ?? 0) * 1000

        return GenerationRecord(
            id: generation.id.uuidString,
            generationSessionsId: generation.sessionId.uuidString,
            sequenceNumber: generation.sequenceNumber,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: promptTokens + completionTokens,
            latencyMs: latencyMs,
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: timeToFirstTokenMs,
            cost: 0.0, // Calculate based on model pricing
            costSaved: 0.0,
            executionTarget: "device", // Default, could be stored in performance
            errorType: nil,
            errorMessage: nil,
            metadata: performanceData,
            createdAt: generation.timestamp,
            syncPending: true
        )
    }

    private func mapRecordToGeneration(_ record: GenerationRecord) throws -> Generation {
        // Deserialize performance data
        var performance: GenerationPerformance?
        if let metadata = record.metadata {
            performance = try JSONDecoder().decode(GenerationPerformance.self, from: metadata)
        }

        return Generation(
            id: UUID(uuidString: record.id) ?? UUID(),
            sessionId: UUID(uuidString: record.generationSessionsId) ?? UUID(),
            sequenceNumber: record.sequenceNumber,
            timestamp: record.createdAt,
            performance: performance
        )
    }
}
