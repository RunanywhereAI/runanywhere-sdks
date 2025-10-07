import Foundation

/// Model information metadata
public struct ModelInfoMetadata {
    public let author: String?
    public let license: String?
    public let tags: [String]
    public let description: String?
    public let trainingDataset: String?
    public let baseModel: String?
    public let quantizationLevel: QuantizationLevel?

    public init(
        author: String? = nil,
        license: String? = nil,
        tags: [String] = [],
        description: String? = nil,
        trainingDataset: String? = nil,
        baseModel: String? = nil,
        quantizationLevel: QuantizationLevel? = nil
    ) {
        self.author = author
        self.license = license
        self.tags = tags
        self.description = description
        self.trainingDataset = trainingDataset
        self.baseModel = baseModel
        self.quantizationLevel = quantizationLevel
    }
}
