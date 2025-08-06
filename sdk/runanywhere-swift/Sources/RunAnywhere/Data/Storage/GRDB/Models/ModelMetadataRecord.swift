import Foundation
import GRDB

/// GRDB record for model_metadata table
struct ModelMetadataRecord: Codable {
    var id: String
    var name: String
    var format: String
    var framework: String
    var sizeBytes: Int64
    var quantization: String?
    var version: String
    var sha256Hash: String?

    // JSON columns
    var capabilities: Data  // JSON blob
    var requirements: Data? // JSON blob

    // Download info
    var downloadURL: String?
    var localPath: String?
    var isDownloaded: Bool
    var downloadDate: Date?

    // Usage tracking
    var lastUsedAt: Date?
    var useCount: Int
    var totalTokensGenerated: Int

    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    var syncPending: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        format: String,
        framework: String,
        sizeBytes: Int64,
        quantization: String? = nil,
        version: String = SDKConstants.DatabaseDefaults.modelVersion,
        sha256Hash: String? = nil,
        capabilities: Data = Data(),
        requirements: Data? = nil,
        downloadURL: String? = nil,
        localPath: String? = nil,
        isDownloaded: Bool = false,
        downloadDate: Date? = nil,
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        totalTokensGenerated: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.framework = framework
        self.sizeBytes = sizeBytes
        self.quantization = quantization
        self.version = version
        self.sha256Hash = sha256Hash
        self.capabilities = capabilities
        self.requirements = requirements
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.isDownloaded = isDownloaded
        self.downloadDate = downloadDate
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.totalTokensGenerated = totalTokensGenerated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }
}

// MARK: - TableRecord
extension ModelMetadataRecord: TableRecord {
    static let databaseTableName = "model_metadata"
}

// MARK: - FetchableRecord
extension ModelMetadataRecord: FetchableRecord { }

// MARK: - PersistableRecord
extension ModelMetadataRecord: PersistableRecord {
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names
extension ModelMetadataRecord {
    enum Columns: String, ColumnExpression {
        case id
        case name
        case format
        case framework
        case sizeBytes = "size_bytes"
        case quantization
        case version
        case sha256Hash = "sha256_hash"
        case capabilities
        case requirements
        case downloadURL = "download_url"
        case localPath = "local_path"
        case isDownloaded = "is_downloaded"
        case downloadDate = "download_date"
        case lastUsedAt = "last_used_at"
        case useCount = "use_count"
        case totalTokensGenerated = "total_tokens_generated"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncPending = "sync_pending"
    }
}

// MARK: - Associations
extension ModelMetadataRecord {
    static let usageStats = hasMany(ModelUsageStatsRecord.self)
}
