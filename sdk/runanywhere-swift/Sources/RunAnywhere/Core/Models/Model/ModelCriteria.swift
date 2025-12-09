import Foundation

/// Model criteria for filtering
public struct ModelCriteria {
    public let framework: LLMFramework?
    public let format: ModelFormat?
    public let maxSize: Int64?
    public let minContextLength: Int?
    public let maxContextLength: Int?
    public let tags: [String]
    public let quantization: String?
    public let search: String?

    public init(
        framework: LLMFramework? = nil,
        format: ModelFormat? = nil,
        maxSize: Int64? = nil,
        minContextLength: Int? = nil,
        maxContextLength: Int? = nil,
        tags: [String] = [],
        quantization: String? = nil,
        search: String? = nil
    ) {
        self.framework = framework
        self.format = format
        self.maxSize = maxSize
        self.minContextLength = minContextLength
        self.maxContextLength = maxContextLength
        self.tags = tags
        self.quantization = quantization
        self.search = search
    }
}
