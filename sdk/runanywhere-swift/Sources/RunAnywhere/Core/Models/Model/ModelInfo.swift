import Foundation
import GRDB

/// Information about a model - database entity with sync support
public struct ModelInfo: Codable, Syncable, RepositoryEntity, FetchableRecord, PersistableRecord {
    // Essential identifiers
    public let id: String
    public let name: String
    public let category: ModelCategory  // Type of model (language, speech, vision, etc.)

    // Format and location
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?

    // Size information (in bytes)
    public let downloadSize: Int64?  // Size when downloading
    public let memoryRequired: Int64?  // RAM needed to run the model

    // Framework compatibility
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?

    // Model-specific capabilities (optional based on category)
    public let contextLength: Int?  // For language models
    public let supportsThinking: Bool  // For reasoning models

    // Optional metadata
    public let metadata: ModelInfoMetadata?

    // Tracking fields for sync and database
    public let source: ConfigurationSource
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    // Usage tracking
    public var lastUsed: Date?
    public var usageCount: Int

    // Non-Codable runtime properties
    public var additionalProperties: [String: Any] = [:]

    // MARK: - Computed Properties

    /// Whether this model is downloaded and available locally
    public var isDownloaded: Bool {
        guard let localPath = localPath else { return false }
        return FileManager.default.fileExists(atPath: localPath.path)
    }

    /// Whether this model is available for use (downloaded and locally accessible)
    public var isAvailable: Bool {
        return isDownloaded
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, format, downloadURL, localPath
        case downloadSize, memoryRequired
        case compatibleFrameworks, preferredFramework
        case contextLength, supportsThinking
        case metadata
        case source, createdAt, updatedAt, syncPending
        case lastUsed, usageCount
    }

    public init(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        downloadSize: Int64? = nil,
        memoryRequired: Int64? = nil,
        compatibleFrameworks: [LLMFramework] = [],
        preferredFramework: LLMFramework? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        metadata: ModelInfoMetadata? = nil,
        source: ConfigurationSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = false,
        lastUsed: Date? = nil,
        usageCount: Int = 0,
        additionalProperties: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.downloadSize = downloadSize
        self.memoryRequired = memoryRequired
        self.compatibleFrameworks = compatibleFrameworks
        self.preferredFramework = preferredFramework ?? compatibleFrameworks.first

        // Set contextLength based on category if not provided
        if category.requiresContextLength {
            self.contextLength = contextLength ?? 2048
        } else {
            self.contextLength = contextLength
        }

        // Set supportsThinking based on category
        self.supportsThinking = category.supportsThinking ? supportsThinking : false

        self.metadata = metadata
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
        self.lastUsed = lastUsed
        self.usageCount = usageCount
        self.additionalProperties = additionalProperties
    }

    // MARK: - Syncable

    public mutating func markUpdated() -> Self {
        self.updatedAt = Date()
        self.syncPending = true
        return self
    }

    public mutating func markSynced() -> Self {
        self.syncPending = false
        return self
    }

    // MARK: - GRDB

    public static var databaseTableName: String { "models" }
}

// MARK: - Database Columns

extension ModelInfo {
    public enum Columns: String, ColumnExpression {
        case id
        case name
        case category
        case format
        case downloadURL
        case localPath
        case downloadSize
        case memoryRequired
        case compatibleFrameworks
        case preferredFramework
        case contextLength
        case supportsThinking
        case metadata
        case source
        case createdAt
        case updatedAt
        case syncPending
        case lastUsed
        case usageCount
    }
}
