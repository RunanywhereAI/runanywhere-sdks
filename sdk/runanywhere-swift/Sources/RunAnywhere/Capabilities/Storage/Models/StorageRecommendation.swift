import Foundation

/// Storage recommendation
public struct StorageRecommendation {
    public let type: RecommendationType
    public let message: String
    public let action: String

    public enum RecommendationType {
        case critical
        case warning
        case suggestion
    }

    public init(type: RecommendationType, message: String, action: String) {
        self.type = type
        self.message = message
        self.action = action
    }
}
