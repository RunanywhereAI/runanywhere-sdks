import Foundation

/// Model information metadata
public struct ModelInfoMetadata: Codable, Sendable {
    public let author: String?
    public let license: String?
    public let tags: [String]
    public let description: String?
    public let trainingDataset: String?
    public let baseModel: String?
    public let version: String?
    public let minOSVersion: String?
    public let minMemory: Int64?

    public init(
        author: String? = nil,
        license: String? = nil,
        tags: [String] = [],
        description: String? = nil,
        trainingDataset: String? = nil,
        baseModel: String? = nil,
        version: String? = nil,
        minOSVersion: String? = nil,
        minMemory: Int64? = nil
    ) {
        self.author = author
        self.license = license
        self.tags = tags
        self.description = description
        self.trainingDataset = trainingDataset
        self.baseModel = baseModel
        self.version = version
        self.minOSVersion = minOSVersion
        self.minMemory = minMemory
    }
}
