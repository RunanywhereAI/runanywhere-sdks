import Foundation

/// Context for maintaining conversation state
public struct Context: Codable {
    /// Previous messages in the conversation
    public let messages: [Message]

    /// System prompt override
    public let systemPrompt: String?

    /// Maximum context window size
    public let maxTokens: Int

    public init(
        messages: [Message] = [],
        systemPrompt: String? = nil,
        maxTokens: Int = 2048
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }
}
