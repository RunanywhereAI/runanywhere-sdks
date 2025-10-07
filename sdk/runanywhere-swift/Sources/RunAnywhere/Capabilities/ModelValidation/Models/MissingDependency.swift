import Foundation

/// Missing dependency information
public struct MissingDependency {
    public let name: String
    public let version: String?
    public let type: DependencyType

    public enum DependencyType {
        case framework
        case library
        case model
        case tokenizer
        case configuration
    }

    public init(name: String, version: String? = nil, type: DependencyType) {
        self.name = name
        self.version = version
        self.type = type
    }
}
