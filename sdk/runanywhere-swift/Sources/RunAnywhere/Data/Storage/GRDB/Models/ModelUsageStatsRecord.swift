import Foundation
import GRDB

/// GRDB record for model_usage_stats table
struct ModelUsageStatsRecord: Codable {
    var id: String
    var modelMetadataId: String
    var date: Date
    var generationCount: Int
    var totalTokens: Int
    var totalCost: Double
    var averageLatencyMs: Double?
    var errorCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case modelMetadataId = "model_metadataId"  // GRDB's belongsTo creates camelCase
        case date
        case generationCount = "generation_count"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
        case averageLatencyMs = "average_latency_ms"
        case errorCount = "error_count"
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        modelMetadataId: String,
        date: Date,
        generationCount: Int = 0,
        totalTokens: Int = 0,
        totalCost: Double = 0.0,
        averageLatencyMs: Double? = nil,
        errorCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.modelMetadataId = modelMetadataId
        self.date = date
        self.generationCount = generationCount
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.averageLatencyMs = averageLatencyMs
        self.errorCount = errorCount
        self.createdAt = createdAt
    }
}

// MARK: - TableRecord
extension ModelUsageStatsRecord: TableRecord {
    static let databaseTableName = "model_usage_stats"
}

// MARK: - FetchableRecord
extension ModelUsageStatsRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension ModelUsageStatsRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension ModelUsageStatsRecord {
    enum Columns: String, ColumnExpression {
        case id
        case modelMetadataId = "model_metadata_id"
        case date
        case generationCount = "generation_count"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
        case averageLatencyMs = "average_latency_ms"
        case errorCount = "error_count"
        case createdAt = "created_at"
    }
}

// MARK: - Associations
extension ModelUsageStatsRecord {
    static let model = belongsTo(ModelMetadataRecord.self)
}
