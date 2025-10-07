import Foundation

/// Persisted model metadata data
public struct ModelMetadataData: RepositoryEntity {
    public let id: String
    public let name: String
    public let format: String
    public let framework: String
    public let localPath: String
    public let estimatedMemory: Int64
    public let contextLength: Int
    public let downloadSize: Int64?
    public let checksum: String?
    public let author: String?
    public let license: String?
    public let description: String?
    public let tags: [String]
    public let downloadedAt: Date
    public let lastUsed: Date?
    public let usageCount: Int
    public let supportsThinking: Bool
    public let thinkingOpenTag: String?
    public let thinkingCloseTag: String?
    public let updatedAt: Date
    public let syncPending: Bool

    public init(
        id: String,
        name: String,
        format: String,
        framework: String,
        localPath: String,
        estimatedMemory: Int64,
        contextLength: Int,
        downloadSize: Int64? = nil,
        checksum: String? = nil,
        author: String? = nil,
        license: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        downloadedAt: Date = Date(),
        lastUsed: Date? = nil,
        usageCount: Int = 0,
        supportsThinking: Bool = false,
        thinkingOpenTag: String? = nil,
        thinkingCloseTag: String? = nil,
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.framework = framework
        self.localPath = localPath
        self.estimatedMemory = estimatedMemory
        self.contextLength = contextLength
        self.downloadSize = downloadSize
        self.checksum = checksum
        self.author = author
        self.license = license
        self.description = description
        self.tags = tags
        self.downloadedAt = downloadedAt
        self.lastUsed = lastUsed
        self.usageCount = usageCount
        self.supportsThinking = supportsThinking
        self.thinkingOpenTag = thinkingOpenTag
        self.thinkingCloseTag = thinkingCloseTag
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

    /// Create from ModelInfo
    public init(from model: ModelInfo) {
        self.id = model.id
        self.name = model.name
        self.format = model.format.rawValue
        self.framework = model.preferredFramework?.rawValue ?? model.compatibleFrameworks.first?.rawValue ?? ""
        self.localPath = model.localPath?.path ?? ""
        self.estimatedMemory = model.estimatedMemory
        self.contextLength = model.contextLength
        self.downloadSize = model.downloadSize
        self.checksum = model.checksum
        self.author = model.metadata?.author
        self.license = model.metadata?.license
        self.description = model.metadata?.description
        self.tags = model.metadata?.tags ?? []
        self.downloadedAt = Date()
        self.lastUsed = nil
        self.usageCount = 0
        self.supportsThinking = model.supportsThinking
        self.thinkingOpenTag = model.thinkingTagPattern?.openingTag
        self.thinkingCloseTag = model.thinkingTagPattern?.closingTag
        self.updatedAt = Date()
        self.syncPending = true
    }
}
