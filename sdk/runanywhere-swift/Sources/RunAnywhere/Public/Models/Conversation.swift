import Foundation

// MARK: - Message

/// A message in a conversation
public struct Message: Sendable {
    /// The role of the message sender
    public let role: MessageRole

    /// The content of the message
    public let content: String

    /// Optional metadata
    public let metadata: [String: String]?

    /// Timestamp when the message was created
    public let timestamp: Date

    public init(
        role: MessageRole,
        content: String,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.role = role
        self.content = content
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

// MARK: - Message Role

/// Role of the message sender
public enum MessageRole: String, Sendable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
}

// MARK: - Context

/// Context for a conversation
public struct Context: Sendable {
    /// System prompt for the conversation
    public let systemPrompt: String?

    /// Previous messages in the conversation
    public let messages: [Message]

    /// Maximum number of messages to keep in context
    public let maxMessages: Int

    /// Additional context metadata
    public let metadata: [String: String]

    public init(
        systemPrompt: String? = nil,
        messages: [Message] = [],
        maxMessages: Int = 100,
        metadata: [String: String] = [:]
    ) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.maxMessages = maxMessages
        self.metadata = metadata
    }

    /// Add a message to the context
    public func adding(message: Message) -> Context {
        var newMessages = messages
        newMessages.append(message)

        // Trim if exceeds max
        if newMessages.count > maxMessages {
            newMessages = Array(newMessages.suffix(maxMessages))
        }

        return Context(
            systemPrompt: systemPrompt,
            messages: newMessages,
            maxMessages: maxMessages,
            metadata: metadata
        )
    }

    /// Clear all messages but keep system prompt
    public func cleared() -> Context {
        return Context(
            systemPrompt: systemPrompt,
            messages: [],
            maxMessages: maxMessages,
            metadata: metadata
        )
    }
}
