import Foundation

// MARK: - Conversation Management

/// Simple conversation manager for multi-turn dialogues with LLM
public class Conversation {
    private var messages: [String] = []
    private let logger = SDKLogger(category: "Conversation")

    public init() {}

    /// Send a message and get response
    /// - Parameter message: The user's message
    /// - Returns: The LLM's response
    public func send(_ message: String) async throws -> String {
        messages.append("User: \(message)")

        let contextPrompt = messages.joined(separator: "\n") + "\nAssistant:"

        // Use the LLM generation service
        let result = try await ServiceContainer.shared.generationService.generate(
            prompt: contextPrompt,
            options: LLMGenerationOptions()
        )

        messages.append("Assistant: \(result.text)")
        logger.debug("Conversation turn completed, history: \(messages.count) messages")

        return result.text
    }

    /// Get conversation history
    public var history: [String] {
        messages
    }

    /// Clear conversation
    public func clear() {
        messages.removeAll()
        logger.debug("Conversation cleared")
    }

    /// Get message count
    public var messageCount: Int {
        messages.count
    }
}
