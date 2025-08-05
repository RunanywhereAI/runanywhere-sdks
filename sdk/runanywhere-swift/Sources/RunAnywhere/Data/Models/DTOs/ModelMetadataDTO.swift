import Foundation

/// Data Transfer Object for model metadata sync
public struct ModelMetadataDTO: Codable {
    public let modelId: String
    public let name: String
    public let version: String
    public let framework: LLMFramework
    public let format: ModelFormat
    public let sizeInBytes: Int64
    public let downloadURLs: [String]
    public let checksum: String?
    public let metadata: ModelMetadataInfo
    public let requirements: ModelRequirementsDTO

    public init(from entity: ModelMetadataData) {
        self.modelId = entity.modelId
        self.name = entity.name
        self.version = entity.version
        self.framework = entity.framework
        self.format = entity.format
        self.sizeInBytes = entity.sizeInBytes
        self.downloadURLs = entity.downloadURLs
        self.checksum = entity.checksum
        self.metadata = ModelMetadataInfo(
            description: entity.description,
            author: entity.author,
            license: entity.license,
            tags: entity.tags
        )
        self.requirements = ModelRequirementsDTO(
            minMemory: entity.minMemory,
            recommendedMemory: entity.recommendedMemory,
            supportedPlatforms: entity.supportedPlatforms
        )
    }
}

/// Model metadata information
public struct ModelMetadataInfo: Codable {
    public let description: String?
    public let author: String?
    public let license: String?
    public let tags: [String]
}

/// Model requirements DTO
public struct ModelRequirementsDTO: Codable {
    public let minMemory: Int64
    public let recommendedMemory: Int64?
    public let supportedPlatforms: [String]
}

/// Response from model catalog query
public struct ModelCatalogResponse: Codable {
    public let models: [ModelMetadataDTO]
    public let totalCount: Int
    public let page: Int
    public let pageSize: Int
    public let lastUpdated: Date
}
