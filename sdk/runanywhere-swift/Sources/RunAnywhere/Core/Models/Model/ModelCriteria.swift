import Foundation

/// Model criteria for filtering
public struct ModelCriteria {
    public let framework: LLMFramework?
    public let format: ModelFormat?
    public let maxSize: Int64?
    public let minContextLength: Int?
    public let maxContextLength: Int?
    public let requiresNeuralEngine: Bool?
    public let requiresGPU: Bool?
    public let tags: [String]
    public let quantization: String?
    public let search: String?

    public init(
        framework: LLMFramework? = nil,
        format: ModelFormat? = nil,
        maxSize: Int64? = nil,
        minContextLength: Int? = nil,
        maxContextLength: Int? = nil,
        requiresNeuralEngine: Bool? = nil,
        requiresGPU: Bool? = nil,
        tags: [String] = [],
        quantization: String? = nil,
        search: String? = nil
    ) {
        self.framework = framework
        self.format = format
        self.maxSize = maxSize
        self.minContextLength = minContextLength
        self.maxContextLength = maxContextLength
        self.requiresNeuralEngine = requiresNeuralEngine
        self.requiresGPU = requiresGPU
        self.tags = tags
        self.quantization = quantization
        self.search = search
    }
}
