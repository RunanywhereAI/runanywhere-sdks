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

    public init(name: String, path: URL, size: Int64, format: ModelFormat, framework: LLMFramework?, createdDate: Date, lastUsed: Date?) {
        self.name = name
        self.path = path
        self.size = size
        self.format = format
        self.framework = framework
        self.createdDate = createdDate
        self.lastUsed = lastUsed
    }
}
