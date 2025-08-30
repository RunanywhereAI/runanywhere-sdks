import Foundation

/// Model storage information
public struct ModelStorageInfo {
    public let totalSize: Int64
    public let modelCount: Int
    public let modelsByFramework: [LLMFramework: [StoredModel]]
    public let largestModel: StoredModel?

    public init(totalSize: Int64, modelCount: Int, modelsByFramework: [LLMFramework: [StoredModel]], largestModel: StoredModel?) {
        self.totalSize = totalSize
        self.modelCount = modelCount
        self.modelsByFramework = modelsByFramework
        self.largestModel = largestModel
    }
}
