import Foundation
import GRDB

/// Information about a model - database entity with sync support
public struct ModelInfo: Codable, RepositoryEntity, FetchableRecord, PersistableRecord, Sendable {
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
    public let compatibleFrameworks: [InferenceFramework]
    public let preferredFramework: InferenceFramework?

    // Model-specific capabilities (optional based on category)
    public let contextLength: Int?  // For language models
    public let supportsThinking: Bool  // For reasoning models
    public let thinkingPattern: ThinkingTagPattern?  // Custom thinking pattern (if supportsThinking)

    // Optional metadata (flattened from ModelInfoMetadata)
    public let tags: [String]
    public let description: String?

    // Tracking fields for sync and database
    public let source: ConfigurationSource
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    // Usage tracking
    public var lastUsed: Date?
    public var usageCount: Int

    // MARK: - Computed Properties

    /// Whether this model is downloaded and available locally
    public var isDownloaded: Bool {
        guard let localPath = localPath else { return false }

        // Built-in models (e.g., Apple Foundation Models) are always available
        if localPath.scheme == "builtin" {
            return true
        }

        // Check if the file or directory actually exists on disk
        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)

        // For directories, verify they contain files (not empty)
        if exists && isDirectory {
            return FileOperationsUtilities.isNonEmptyDirectory(at: localPath)
        }

        return exists
    }

    /// Whether this model is available for use (downloaded and locally accessible)
    public var isAvailable: Bool {
        isDownloaded
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, format, downloadURL, localPath
        case downloadSize, memoryRequired
        case compatibleFrameworks, preferredFramework
        case contextLength, supportsThinking, thinkingPattern
        case tags, description
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
        compatibleFrameworks: [InferenceFramework] = [],
        preferredFramework: InferenceFramework? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        thinkingPattern: ThinkingTagPattern? = nil,
        tags: [String] = [],
        description: String? = nil,
        source: ConfigurationSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = false,
        lastUsed: Date? = nil,
        usageCount: Int = 0
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

        // Set thinking pattern based on supportsThinking
        self.thinkingPattern = supportsThinking ? (thinkingPattern ?? .defaultPattern) : nil

        self.tags = tags
        self.description = description
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
        self.lastUsed = lastUsed
        self.usageCount = usageCount
    }

    // MARK: - Sync methods provided by RepositoryEntity protocol extension

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
        case thinkingPattern
        case tags
        case description
        case source
        case createdAt
        case updatedAt
        case syncPending
        case lastUsed
        case usageCount
    }
}
