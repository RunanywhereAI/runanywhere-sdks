import Foundation

/// Message in a conversation
public struct Message: Codable {
    /// Role of the message sender
    public let role: Role

    /// Content of the message
    public let content: String

    /// Timestamp
    public let timestamp: Date

    public enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    public init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
