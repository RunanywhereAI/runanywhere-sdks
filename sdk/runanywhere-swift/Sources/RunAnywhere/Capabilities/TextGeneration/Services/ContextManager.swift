import Foundation

/// Manages conversation context for generation
public class ContextManager {

    public init() {}

    /// Prepare context for generation
    public func prepareContext(
        prompt: String,
        options: GenerationOptions
    ) async throws -> Context {
        // Use provided context or create new one
        if let existingContext = options.context {
            // Append new user message
            var messages = existingContext.messages
            messages.append(Message(role: .user, content: prompt))

            return Context(
                messages: messages,
                systemPrompt: existingContext.systemPrompt,
                maxTokens: existingContext.maxTokens
            )
        } else {
            // Create new context
            return Context(
                messages: [Message(role: .user, content: prompt)],
                systemPrompt: nil,
                maxTokens: options.maxTokens
            )
        }
    }

    /// Update context with generation result
    public func updateContext(
        _ context: Context,
        with response: String
    ) -> Context {
        var messages = context.messages
        messages.append(Message(role: .assistant, content: response))

        return Context(
            messages: messages,
            systemPrompt: context.systemPrompt,
            maxTokens: context.maxTokens
        )
    }

    /// Trim context to fit within token limits
    public func trimContext(
        _ context: Context,
        maxTokens: Int
    ) -> Context {
        // Simple implementation: keep most recent messages
        var messages = context.messages

        // Keep system prompt and trim from oldest messages
        while messages.count > 2 && estimateTokenCount(messages) > maxTokens {
            messages.removeFirst()
        }

        return Context(
            messages: messages,
            systemPrompt: context.systemPrompt,
            maxTokens: context.maxTokens
        )
    }

    private func estimateTokenCount(_ messages: [Message]) -> Int {
        // Simple estimation: ~4 characters per token
        let totalChars = messages.reduce(0) { total, message in
            total + message.content.count
        }
        return totalChars / 4
    }
}
