import Foundation
import GRDB

/// GRDB record for generations table
struct GenerationRecord: Codable {
    var id: String
    var generationSessionsId: String
    var sequenceNumber: Int

    // Token counts
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int

    // Performance metrics
    var latencyMs: Double
    var tokensPerSecond: Double?
    var timeToFirstTokenMs: Double?

    // Cost tracking
    var cost: Double
    var costSaved: Double

    // Execution details
    var executionTarget: String
    var routingReason: String?
    var frameworkUsed: String?

    // Request/Response data
    var requestData: Data? // JSON blob
    var responseData: Data? // JSON blob

    // Error tracking
    var errorCode: String?
    var errorMessage: String?

    // Timestamps
    var createdAt: Date
    var syncPending: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case generationSessionsId = "generation_sessionsId"  // GRDB's belongsTo creates camelCase
        case sequenceNumber = "sequence_number"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case latencyMs = "latency_ms"
        case tokensPerSecond = "tokens_per_second"
        case timeToFirstTokenMs = "time_to_first_token_ms"
        case cost
        case costSaved = "cost_saved"
        case executionTarget = "execution_target"
        case routingReason = "routing_reason"
        case frameworkUsed = "framework_used"
        case requestData = "request_data"
        case responseData = "response_data"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case syncPending = "sync_pending"
    }

    init(
        id: String = UUID().uuidString,
        generationSessionsId: String,
        sequenceNumber: Int,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        latencyMs: Double,
        tokensPerSecond: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        cost: Double = 0.0,
        costSaved: Double = 0.0,
        executionTarget: String = "onDevice",
        routingReason: String? = nil,
        frameworkUsed: String? = nil,
        requestData: Data? = nil,
        responseData: Data? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.generationSessionsId = generationSessionsId
        self.sequenceNumber = sequenceNumber
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.latencyMs = latencyMs
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.cost = cost
        self.costSaved = costSaved
        self.executionTarget = executionTarget
        self.routingReason = routingReason
        self.frameworkUsed = frameworkUsed
        self.requestData = requestData
        self.responseData = responseData
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.syncPending = syncPending
    }
}

// MARK: - TableRecord
extension GenerationRecord: TableRecord {
    static let databaseTableName = "generations"
}

// MARK: - FetchableRecord
extension GenerationRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension GenerationRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension GenerationRecord {
    enum Columns: String, ColumnExpression {
        case id
        case generationSessionsId = "generation_sessions_id"
        case sequenceNumber = "sequence_number"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case latencyMs = "latency_ms"
        case tokensPerSecond = "tokens_per_second"
        case timeToFirstTokenMs = "time_to_first_token_ms"
        case cost
        case costSaved = "cost_saved"
        case executionTarget = "execution_target"
        case routingReason = "routing_reason"
        case frameworkUsed = "framework_used"
        case requestData = "request_data"
        case responseData = "response_data"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case syncPending = "sync_pending"
    }
}

// MARK: - Associations
extension GenerationRecord {
    static let session = belongsTo(GenerationSessionRecord.self)

    var session: QueryInterfaceRequest<GenerationSessionRecord> {
        request(for: GenerationRecord.session)
    }
}
