import Foundation

/// Model metadata extracted during validation
public struct ModelMetadata {
    public var author: String?
    public var description: String?
    public var version: String?
    public var modelType: String?
    public var architecture: String?
    public var quantization: String?
    public var contextLength: Int?
    public var vocabularySize: Int?
    public var embeddingDimension: Int?
    public var layers: Int?
    public var parameters: Int64?
    public var parameterCount: Int64?
    public var formatVersion: String?
    public var tensorCount: Int?
    public var inputShapes: [String: [Int]]?
    public var outputShapes: [String: [Int]]?
    public var license: String?
    public var tags: [String]?
    public var createdDate: Date?
    public var lastModified: Date?
    public var checksum: String?
    public var requirements: ModelRequirements?
    public var additionalInfo: [String: Any]?

    public init(
        author: String? = nil,
        description: String? = nil,
        version: String? = nil,
        modelType: String? = nil,
        architecture: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil,
        vocabularySize: Int? = nil,
        embeddingDimension: Int? = nil,
        layers: Int? = nil,
        parameters: Int64? = nil,
        parameterCount: Int64? = nil,
        formatVersion: String? = nil,
        tensorCount: Int? = nil,
        inputShapes: [String: [Int]]? = nil,
        outputShapes: [String: [Int]]? = nil,
        license: String? = nil,
        tags: [String]? = nil,
        createdDate: Date? = nil,
        lastModified: Date? = nil,
        checksum: String? = nil,
        requirements: ModelRequirements? = nil,
        additionalInfo: [String: Any]? = nil
    ) {
        self.author = author
        self.description = description
        self.version = version
        self.modelType = modelType
        self.architecture = architecture
        self.quantization = quantization
        self.contextLength = contextLength
        self.vocabularySize = vocabularySize
        self.embeddingDimension = embeddingDimension
        self.layers = layers
        self.parameters = parameters
        self.parameterCount = parameterCount
        self.formatVersion = formatVersion
        self.tensorCount = tensorCount
        self.inputShapes = inputShapes
        self.outputShapes = outputShapes
        self.license = license
        self.tags = tags
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.checksum = checksum
        self.requirements = requirements
        self.additionalInfo = additionalInfo
    }
}
