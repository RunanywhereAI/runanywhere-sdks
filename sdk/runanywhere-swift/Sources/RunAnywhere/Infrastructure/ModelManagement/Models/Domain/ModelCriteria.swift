import Foundation

/// Model criteria for filtering
public struct ModelCriteria {
    public let framework: InferenceFramework?
    public let format: ModelFormat?
    public let maxSize: Int64?
    public let tags: [String]
    public let search: String?

    public init(
        framework: InferenceFramework? = nil,
        format: ModelFormat? = nil,
        maxSize: Int64? = nil,
        tags: [String] = [],
        search: String? = nil
    ) {
        self.framework = framework
        self.format = format
        self.maxSize = maxSize
        self.tags = tags
        self.search = search
    }
}
