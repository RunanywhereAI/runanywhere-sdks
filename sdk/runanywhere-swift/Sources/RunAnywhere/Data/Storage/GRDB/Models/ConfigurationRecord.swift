import Foundation
import GRDB

/// GRDB record for configuration table
struct ConfigurationRecord: Codable {
    var id: String
    var apiKey: String?
    var baseURL: String
    var modelCacheSize: Int
    var maxMemoryUsageMB: Int
    var privacyMode: String
    var telemetryConsent: String
    var createdAt: Date
    var updatedAt: Date
    var syncPending: Bool

    init(
        id: String = UUID().uuidString,
        apiKey: String? = nil,
        baseURL: String = "https://api.runanywhere.ai",
        modelCacheSize: Int = 5,
        maxMemoryUsageMB: Int = 1024,
        privacyMode: String = "standard",
        telemetryConsent: String = "anonymous",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelCacheSize = modelCacheSize
        self.maxMemoryUsageMB = maxMemoryUsageMB
        self.privacyMode = privacyMode
        self.telemetryConsent = telemetryConsent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }
}

// MARK: - TableRecord
extension ConfigurationRecord: TableRecord {
    static let databaseTableName = "configuration"
}

// MARK: - FetchableRecord
extension ConfigurationRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension ConfigurationRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension ConfigurationRecord {
    enum Columns: String, ColumnExpression {
        case id
        case apiKey = "api_key"
        case baseURL = "base_url"
        case modelCacheSize = "model_cache_size"
        case maxMemoryUsageMB = "max_memory_usage_mb"
        case privacyMode = "privacy_mode"
        case telemetryConsent = "telemetry_consent"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncPending = "sync_pending"
    }
}
