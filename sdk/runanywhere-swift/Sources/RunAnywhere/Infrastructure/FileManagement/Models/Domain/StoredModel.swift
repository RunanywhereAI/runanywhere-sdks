import Foundation

/// Stored model information
public struct StoredModel: Sendable {
    public let id: String  // Model ID used for operations like deletion
    public let name: String
    public let path: URL
    public let size: Int64
    public let format: ModelFormat
    public let framework: LLMFramework?
    public let createdDate: Date
    public let lastUsed: Date?
    public let tags: [String]
    public let description: String?
    public let contextLength: Int?
    public let checksum: String?

    public init(
        id: String,
        name: String,
        path: URL,
        size: Int64,
        format: ModelFormat,
        framework: LLMFramework?,
        createdDate: Date,
        lastUsed: Date?,
        tags: [String] = [],
        description: String? = nil,
        contextLength: Int? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.format = format
        self.framework = framework
        self.createdDate = createdDate
        self.lastUsed = lastUsed
        self.tags = tags
        self.description = description
        self.contextLength = contextLength
        self.checksum = checksum
    }
}
