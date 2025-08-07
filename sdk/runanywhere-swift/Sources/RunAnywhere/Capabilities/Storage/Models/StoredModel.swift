import Foundation

/// Stored model information
public struct StoredModel {
    public let name: String
    public let path: URL
    public let size: Int64
    public let format: ModelFormat
    public let framework: LLMFramework?
    public let createdDate: Date
    public let lastUsed: Date?
    public let metadata: ModelInfoMetadata?
    public let contextLength: Int?
    public let checksum: String?

    public init(
        name: String,
        path: URL,
        size: Int64,
        format: ModelFormat,
        framework: LLMFramework?,
        createdDate: Date,
        lastUsed: Date?,
        metadata: ModelInfoMetadata? = nil,
        contextLength: Int? = nil,
        checksum: String? = nil
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.format = format
        self.framework = framework
        self.createdDate = createdDate
        self.lastUsed = lastUsed
        self.metadata = metadata
        self.contextLength = contextLength
        self.checksum = checksum
    }
}
