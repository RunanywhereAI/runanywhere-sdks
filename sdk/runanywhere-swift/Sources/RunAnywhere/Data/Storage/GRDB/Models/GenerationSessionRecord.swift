import Foundation
import GRDB

/// GRDB record for generation_sessions table
struct GenerationSessionRecord: Codable {
    var id: String
    var modelMetadataId: String
    var sessionType: String
    var totalTokens: Int
    var totalCost: Double
    var messageCount: Int
    var contextData: Data? // JSON blob
    var startedAt: Date
    var endedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncPending: Bool

    init(
        id: String = UUID().uuidString,
        modelMetadataId: String,
        sessionType: String = "chat",
        totalTokens: Int = 0,
        totalCost: Double = 0.0,
        messageCount: Int = 0,
        contextData: Data? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.modelMetadataId = modelMetadataId
        self.sessionType = sessionType
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.messageCount = messageCount
        self.contextData = contextData
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }
}

// MARK: - TableRecord
extension GenerationSessionRecord: TableRecord {
    static let databaseTableName = "generation_sessions"
}

// MARK: - FetchableRecord
extension GenerationSessionRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension GenerationSessionRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension GenerationSessionRecord {
    enum Columns: String, ColumnExpression {
        case id
        case modelMetadataId = "model_metadata_id"
        case sessionType = "session_type"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
        case messageCount = "message_count"
        case contextData = "context_data"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncPending = "sync_pending"
    }
}

// MARK: - Associations
extension GenerationSessionRecord {
    static let model = belongsTo(ModelMetadataRecord.self)
    static let generations = hasMany(GenerationRecord.self)

    var model: QueryInterfaceRequest<ModelMetadataRecord> {
        request(for: GenerationSessionRecord.model)
    }

    var generations: QueryInterfaceRequest<GenerationRecord> {
        request(for: GenerationSessionRecord.generations)
    }
}
